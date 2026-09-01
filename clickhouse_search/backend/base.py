import copy
from collections.abc import Mapping

from clickhouse_backend.backend.base import (
    DatabaseWrapper as BaseDatabaseWrapper,
    DatabaseSchemaEditor as BaseDatabaseSchemaEditor,
)
from clickhouse_backend.backend.introspection import (
    DatabaseIntrospection as BaseDatabaseIntrospection,
    TableInfo,
)
from clickhouse_backend.backend.operations import DatabaseOperations as BaseDatabaseOperations
from django.utils.itercompat import is_iterable

from clickhouse_search.backend.engines import Join

class DatabaseSchemaEditor(BaseDatabaseSchemaEditor):

    def _model_extra_sql(self, model, engine):
        # BaseMergeTree.__init__ normalises order_by and primary_key from a bare string
        # to a list, but leaves partition_by untouched. The base _model_extra_sql then
        # splats it -- `self._get_expression(model, *partition_by)` -- so a string is
        # unpacked into individual characters and the first one fails to resolve as a
        # field name ("Cannot resolve keyword 'p' into field"). Normalise it the same
        # way order_by is normalised.
        partition_by = getattr(engine, 'partition_by', None)
        if partition_by is not None and (
            isinstance(partition_by, str) or not is_iterable(partition_by)
        ):
            # Copy rather than mutate in place: the engine is part of the migration
            # state that the autodetector deconstructs, so it has to keep comparing
            # equal to the value written in the migration file.
            engine = copy.copy(engine)
            engine.partition_by = [partition_by]
        yield from super()._model_extra_sql(model, engine)

    def table_sql(self, model):
        sql, params = super().table_sql(model)
        # Make table creation idempotent so migrations don't fail on re-run
        sql = sql.replace('CREATE TABLE', 'CREATE TABLE IF NOT EXISTS', 1)
        projection = getattr(model._meta, 'projection', None)
        if projection:
            sql = sql.replace(
                ') ENGINE',
                f', PROJECTION {projection.name} (SELECT {projection.select} ORDER BY {projection.order_by})) ENGINE',
            )
        return sql, params

    def _get_engine_expression(self, model, engine):
        prev_quote_value = self.quote_value   # pylint: disable=access-member-before-definition
        if isinstance(engine, Join):
            self.quote_value = self.no_quote_value
        expression = super()._get_engine_expression(model, self._resolve_engine(model, engine))
        self.quote_value = prev_quote_value
        return expression

    @staticmethod
    def _resolve_engine(model, engine):
        """Resolve the engine's arguments before the base class compiles them.

        Func._parse_expressions turns a plain string argument into an F(), so
        CollapsingMergeTree('sign') holds F('sign'). Only a few engines
        (Graphite/Replicated/Distributed) run their arguments through
        value_if_string, and the base _get_engine_expression compiles the engine
        without ever calling resolve_expression -- F has no as_sql(), so compiling
        raises "'F' object has no attribute 'as_sql'".

        Resolving against the model's query first mirrors what _get_expression()
        already does for order_by/partition_by, and turns F('sign') into a Col that
        compiles to the quoted column name. Value() arguments (used by the
        EmbeddedRocksDB and Join engines) resolve to themselves, so they are
        unaffected.
        """
        from clickhouse_backend.models.sql import Query

        return engine.resolve_expression(Query(model, alias_cols=False))

    def no_quote_value(self, value):
        return value


class DatabaseOperations(BaseDatabaseOperations):

    def last_executed_query(self, cursor, sql, params):
        # The base implementation does `sql % tuple(params)`, which raises
        # "TypeError: format requires a mapping" when params is a dict -- i.e. whenever
        # a query uses %(name)s placeholders. This only runs under DEBUG (it builds the
        # message for the django.db.backends logger), but the exception propagates out
        # of cursor.execute() and aborts the migration that issued the query.
        if isinstance(params, Mapping):
            return sql % params
        return super().last_executed_query(cursor, sql, params)


class DatabaseIntrospection(BaseDatabaseIntrospection):

    def get_table_list(self, cursor):
        """Return a list of table and view names in the current database.

        The base implementation filters `table_type IN (1, 2)`, which assumes
        INFORMATION_SCHEMA.TABLES.table_type is the numeric Enum8 that older ClickHouse
        exposed. ClickHouse 25.x returns a String ('BASE TABLE' / 'VIEW' /
        'FOREIGN TABLE'), so that filter matches nothing and the table list comes back
        empty. That silently breaks MigrationRecorder.has_table(), which makes
        applied_migrations() return {} -- so every migration is re-applied on every
        boot, failing on whichever operation is not idempotent.

        Comparing against the string labels works on both: ClickHouse resolves enum
        names in an IN clause, so this is correct for the old Enum8 column too.
        """
        cursor.execute(
            """
            SELECT table_name,
            CASE table_type WHEN 'VIEW' THEN 'v' ELSE 't' END
            FROM INFORMATION_SCHEMA.TABLES
            WHERE table_catalog = currentDatabase()
            AND table_type IN ('BASE TABLE', 'VIEW')
        """
        )
        return [
            TableInfo(*row)
            for row in cursor.fetchall()
            if row[0] not in self.ignored_tables
        ]


class DatabaseWrapper(BaseDatabaseWrapper):
    SchemaEditorClass = DatabaseSchemaEditor
    ops_class = DatabaseOperations
    introspection_class = DatabaseIntrospection
