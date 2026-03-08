from django.core.management.base import BaseCommand
from django.db import connections


class Command(BaseCommand):
    help = 'Sync clickhouse_search migration records from PostgreSQL to ClickHouse'

    def handle(self, *args, **options):
        pg_cursor = connections['default'].cursor()
        ch_cursor = connections['clickhouse_write'].cursor()

        # Ensure django_migrations table exists in ClickHouse
        try:
            ch_cursor.execute('SELECT count() FROM django_migrations')
        except Exception:
            self.stdout.write('Creating django_migrations table in ClickHouse...')
            ch_cursor.execute('''
                CREATE TABLE IF NOT EXISTS django_migrations (
                    id UInt32,
                    app String,
                    name String,
                    applied DateTime
                ) ENGINE = MergeTree() ORDER BY id
            ''')

        # Get clickhouse_search migrations already recorded in ClickHouse
        ch_cursor.execute("SELECT name FROM django_migrations WHERE app = 'clickhouse_search'")
        ch_applied = {row[0] for row in ch_cursor.fetchall()}

        # Get clickhouse_search migrations recorded in PostgreSQL
        pg_cursor.execute("SELECT id, name, applied FROM django_migrations WHERE app = 'clickhouse_search'")
        synced = 0
        for pg_id, pg_name, pg_applied in pg_cursor.fetchall():
            if pg_name not in ch_applied:
                ch_cursor.execute(
                    'INSERT INTO django_migrations (id, app, name, applied) VALUES',
                    [(pg_id, 'clickhouse_search', pg_name, pg_applied)]
                )
                self.stdout.write(f'  Synced: clickhouse_search.{pg_name}')
                synced += 1

        if synced:
            self.stdout.write(self.style.SUCCESS(f'Synced {synced} migration(s) to ClickHouse'))
        else:
            self.stdout.write(self.style.SUCCESS(
                f'ClickHouse migration state is up to date ({len(ch_applied)} migrations)'
            ))
