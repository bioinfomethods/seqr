from datetime import timezone as dt_timezone

from django.core.management.base import BaseCommand
from django.db import connections
from django.db.migrations.recorder import MigrationRecorder
from django.utils import timezone

APP_LABEL = 'clickhouse_search'

# Columns the ClickHouse MigrationRecorder model requires. django-clickhouse-backend
# patches MigrationRecorder.Migration to add `deleted` and to use DateTime64 for
# `applied`; older revisions of this command hand-rolled the table with a plain
# DateTime and no `deleted`, which made every later INSERT fail with
# "Code: 16 ... No such column deleted".
REQUIRED_COLUMNS = {'id', 'app', 'name', 'applied', 'deleted'}


class Command(BaseCommand):
    """One-shot repair for ClickHouse installs that predate ClickHouse-side bookkeeping.

    PostgreSQL's django_migrations is NOT a usable source of ClickHouse migration state.
    `manage.py migrate` records every migration it walks, including clickhouse_search,
    even though the router skips the operations - MigrationExecutor.record_migration()
    is unconditional. So PostgreSQL always ends up claiming clickhouse_search migrations
    are applied when nothing ran against ClickHouse at all.

    Copying those rows over marks the DDL applied without running it, and `migrate` then
    silently does nothing: dictionaries, materialized views and columns from 0016 onward
    never get created, and searches return wrong results with no error anywhere.

    This command therefore only acts in the one situation it was written for: ClickHouse
    holds real tables but has no clickhouse_search bookkeeping of its own, i.e. a database
    built before the ClickHouse MigrationRecorder existed. In every other case ClickHouse's
    own django_migrations is authoritative and is left untouched.
    """

    help = (
        'Legacy repair: adopt PostgreSQL clickhouse_search migration records only when '
        'ClickHouse has tables but no migration bookkeeping of its own.'
    )

    def handle(self, *args, **options):
        connection = connections['clickhouse_write']
        recorder = MigrationRecorder(connection)

        self._ensure_current_schema(connection, recorder)

        if self._is_empty_database(connection):
            # Nothing has ever been built here. Copying PostgreSQL's rows would mark every
            # migration applied against an empty database, so `migrate` would create
            # nothing at all. Leave the state empty and let migrate build it.
            self.stdout.write(self.style.WARNING(
                'ClickHouse has no clickhouse_search tables - skipping sync so that '
                'migrate can create them from scratch.'
            ))
            return

        # Migrations already recorded in ClickHouse. migration_qs filters deleted=False.
        ch_applied = set(
            recorder.migration_qs.filter(app=APP_LABEL).values_list('name', flat=True)
        )

        if ch_applied:
            # ClickHouse is tracking its own state, so it is the only trustworthy record.
            # Importing PostgreSQL's no-op rows here is what silently skips real DDL - for
            # example a boot where migration 0016 failed leaves ClickHouse at 0015 while
            # PostgreSQL claims 0023, and syncing would bury the failure permanently.
            self.stdout.write(self.style.SUCCESS(
                f'ClickHouse tracks its own migration state ({len(ch_applied)} recorded); '
                'nothing to adopt from PostgreSQL.'
            ))
            return

        self.stdout.write(
            'ClickHouse has tables but no clickhouse_search bookkeeping - adopting the '
            'PostgreSQL records once.'
        )

        with connections['default'].cursor() as pg_cursor:
            pg_cursor.execute(
                'SELECT name, applied FROM django_migrations WHERE app = %s ORDER BY id',
                [APP_LABEL],
            )
            pg_rows = pg_cursor.fetchall()

        for name, applied in pg_rows:
            # Preserve PostgreSQL's original timestamp rather than stamping now(),
            # so the two stores stay comparable.
            recorder.migration_qs.create(app=APP_LABEL, name=name, applied=applied)
            self.stdout.write(f'  Adopted: {APP_LABEL}.{name}')

        if pg_rows:
            self.stdout.write(self.style.SUCCESS(
                f'Adopted {len(pg_rows)} migration record(s) from PostgreSQL'
            ))
        else:
            self.stdout.write(self.style.WARNING(
                'PostgreSQL has no clickhouse_search records to adopt; migrate will '
                'attempt to apply every migration.'
            ))

    @staticmethod
    def _is_empty_database(connection):
        """True when ClickHouse holds nothing but the migration bookkeeping table."""
        with connection.cursor() as cursor:
            cursor.execute(
                'SELECT count() FROM system.tables WHERE database = currentDatabase() '
                "AND name != 'django_migrations'"
            )
            return cursor.fetchone()[0] == 0

    def _ensure_current_schema(self, connection, recorder):
        """Create django_migrations, rebuilding it first if it predates the current schema.

        Deliberately inspects system.columns rather than recorder.has_table():
        has_table() reports False for this table even when it physically exists, and
        ensure_schema() emits CREATE TABLE IF NOT EXISTS, so a table left over from an
        older schema would silently survive both checks and then break every INSERT.
        """
        with connection.cursor() as cursor:
            cursor.execute(
                'SELECT name FROM system.columns WHERE database = currentDatabase() '
                "AND table = 'django_migrations'"
            )
            columns = {row[0] for row in cursor.fetchall()}

        if not columns:
            recorder.ensure_schema()
            return

        missing = REQUIRED_COLUMNS - columns
        if not missing:
            return

        self.stdout.write(
            f'django_migrations is missing {sorted(missing)}; rebuilding with the current schema...'
        )
        with connection.cursor() as cursor:
            cursor.execute('SELECT app, name, applied FROM django_migrations')
            existing = cursor.fetchall()
            cursor.execute('DROP TABLE django_migrations SYNC')

        recorder.ensure_schema()
        for app, name, applied in existing:
            # the old column was a naive DateTime; the new one is DateTime64(6, 'UTC')
            if timezone.is_naive(applied):
                applied = timezone.make_aware(applied, dt_timezone.utc)
            recorder.migration_qs.create(app=app, name=name, applied=applied)
        self.stdout.write(f'  Preserved {len(existing)} existing record(s)')
