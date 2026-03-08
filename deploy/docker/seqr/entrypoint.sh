#!/usr/bin/env bash

set -x

env

echo SHELL: "$SHELL"
echo PATH: "$PATH"
echo PYTHONPATH: "$PYTHONPATH"

# init gcloud
if [ "$GCLOUD_PROJECT" ]; then
    gcloud config set project "$GCLOUD_PROJECT"
fi

if [ "$GCLOUD_ZONE" ]; then
    gcloud config set compute/zone "$GCLOUD_ZONE"
fi

cd /seqr

# allow pg_dump and other postgres command-line tools to run without having to enter a password
echo "*:*:*:*:$POSTGRES_PASSWORD" > ~/.pgpass
chmod 600 ~/.pgpass
cat ~/.pgpass

# wait for database connectivity, exit if we don't get it within ~2 minutes
pg_retries=0
until [ "$pg_retries" -ge 10 ]
do
    pg_isready -d postgres -h "$POSTGRES_SERVICE_HOSTNAME" -U "$POSTGRES_USERNAME" && break
    pg_retries=$((pg_retries+1))
    if [ "$pg_retries" -eq 10 ]; then
        echo "Postgres database wasn't available after 10 connection attempts"
        exit 1
    else
        echo "Unable to connect to postgres, retrying. Attempt ${pg_retries}/10"
        sleep 12
    fi
done

# run any pending migrations
# Run ClickHouse migrations FIRST, before PostgreSQL migrations.
# Django's router should prevent clickhouse_search migrations from running on PostgreSQL,
# but if they do run (as no-ops), they get recorded in PostgreSQL's django_migrations table.
# By running ClickHouse migrations first, the actual DDL executes against ClickHouse.
if [ "$CLICKHOUSE_SERVICE_HOSTNAME" ]; then
    # Sync any previously-recorded migration state from PostgreSQL to ClickHouse
    python -u manage.py sync_clickhouse_migrations
    python -u manage.py migrate --database=clickhouse_write
fi
python -u manage.py migrate
python -u manage.py migrate --database=reference_data

# load initial fixture data only if tables are empty (idempotent boot)
variant_search_count=$(python -u manage.py shell -c "from seqr.models import VariantSearch; print(VariantSearch.objects.count())")
if [ "$variant_search_count" = "0" ]; then
    echo "Loading variant_searches fixture (table is empty)..."
    python -u manage.py loaddata variant_searches
else
    echo "Skipping variant_searches fixture ($variant_search_count records already exist)"
fi

variant_tag_type_count=$(python -u manage.py shell -c "from seqr.models import VariantTagType; print(VariantTagType.objects.count())")
if [ "$variant_tag_type_count" = "0" ]; then
    echo "Loading variant_tag_types fixture (table is empty)..."
    python -u manage.py loaddata variant_tag_types
else
    echo "Skipping variant_tag_types fixture ($variant_tag_type_count records already exist)"
fi

python -u manage.py check

# launch django server in background
/usr/local/bin/start_server.sh

# sleep to keep image running even if gunicorn is killed / restarted
sleep 1000000000000
