from datetime import datetime

from django.core.management.base import BaseCommand
from django.db import connections


class Command(BaseCommand):
    help = 'Sync clickhouse_search migration records from PostgreSQL to ClickHouse'

    def handle(self, *args, **options):
        pg_cursor = connections['default'].cursor()
        ch_cursor = connections['clickhouse_write'].cursor()

        # Ensure django_migrations table exists in ClickHouse with correct schema.
        # Django's MigrationRecorder uses Int64 for the id column, so we must match.
        try:
            ch_cursor.execute('SELECT count() FROM django_migrations')
            # Check if table has old UInt32 schema and recreate with Int64
            ch_cursor.execute("SELECT type FROM system.columns WHERE database = 'seqr' AND table = 'django_migrations' AND name = 'id'")
            id_type = ch_cursor.fetchone()
            if id_type and id_type[0] == 'UInt32':
                self.stdout.write('Recreating django_migrations table with Int64 id column...')
                # Save existing data
                ch_cursor.execute('SELECT id, app, name, applied FROM django_migrations')
                existing_rows = ch_cursor.fetchall()
                ch_cursor.execute('DROP TABLE django_migrations')
                ch_cursor.execute('''
                    CREATE TABLE django_migrations (
                        id Int64,
                        app String,
                        name String,
                        applied DateTime
                    ) ENGINE = MergeTree() ORDER BY id
                ''')
                for row in existing_rows:
                    applied = row[3]
                    if hasattr(applied, 'replace'):
                        applied = applied.replace(tzinfo=None)
                    ch_cursor.execute(
                        'INSERT INTO django_migrations (id, app, name, applied) VALUES',
                        [(row[0], row[1], row[2], applied)]
                    )
                self.stdout.write(f'  Migrated {len(existing_rows)} existing records')
        except Exception:
            self.stdout.write('Creating django_migrations table in ClickHouse...')
            ch_cursor.execute('''
                CREATE TABLE IF NOT EXISTS django_migrations (
                    id Int64,
                    app String,
                    name String,
                    applied DateTime
                ) ENGINE = MergeTree() ORDER BY id
            ''')

        # Get clickhouse_search migrations already recorded in ClickHouse
        ch_cursor.execute("SELECT name FROM django_migrations WHERE app = 'clickhouse_search'")
        ch_applied = {row[0] for row in ch_cursor.fetchall()}

        # Get next available ID in ClickHouse
        ch_cursor.execute('SELECT max(id) FROM django_migrations')
        max_id = ch_cursor.fetchone()[0]
        next_id = (max_id if max_id else 0) + 1

        # Get clickhouse_search migrations recorded in PostgreSQL
        pg_cursor.execute("SELECT name, applied FROM django_migrations WHERE app = 'clickhouse_search' ORDER BY id")
        synced = 0
        for pg_name, pg_applied in pg_cursor.fetchall():
            if pg_name not in ch_applied:
                # Convert timezone-aware datetime to naive datetime for ClickHouse DateTime column
                if hasattr(pg_applied, 'replace'):
                    pg_applied = pg_applied.replace(tzinfo=None)
                ch_cursor.execute(
                    'INSERT INTO django_migrations (id, app, name, applied) VALUES',
                    [(next_id, 'clickhouse_search', pg_name, pg_applied)]
                )
                self.stdout.write(f'  Synced: clickhouse_search.{pg_name}')
                next_id += 1
                synced += 1

        if synced:
            self.stdout.write(self.style.SUCCESS(f'Synced {synced} migration(s) to ClickHouse'))
        else:
            self.stdout.write(self.style.SUCCESS(
                f'ClickHouse migration state is up to date ({len(ch_applied)} migrations)'
            ))
