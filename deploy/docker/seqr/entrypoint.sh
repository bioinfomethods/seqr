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
# PostgreSQL MUST be migrated before ClickHouse. clickhouse_search migration 0016 creates
# `seqrdb_affected_status_dict` (and 0023 `seqrdb_sex_dict`) with a POSTGRESQL() source that
# reads seqr_individual/seqr_family, then creates the entries_to_project_gt_stats_mv
# materialized views that call dictGetOrDefault() on it. ClickHouse resolves - and therefore
# eagerly LOADS - a dictionary when it analyses the CREATE MATERIALIZED VIEW, so against an
# unmigrated PostgreSQL the DDL dies with:
#   Code: 156. Failed to load dictionary ...: pqxx::undefined_table,
#   e.what() = ERROR: relation "seqr_individual" does not exist
# ClickHouse has no transactional DDL, so 0016 half-applies (the DROPs and ALTERs land, the
# CREATEs do not) and the GRCh37 gt_stats pipeline is left missing.
#
# Running PostgreSQL first does mean Django records the clickhouse_search migrations in
# PostgreSQL's django_migrations as skipped no-ops (record_applied() is unconditional; the
# router only suppresses the operations). Those rows are harmless: ClickHouse keeps its own
# django_migrations and that is the authoritative record. sync_clickhouse_migrations below
# deliberately ignores them once ClickHouse has bookkeeping of its own.
python -u manage.py migrate
python -u manage.py migrate --database=reference_data
if [ "$CLICKHOUSE_SERVICE_HOSTNAME" ]; then
    # Legacy repair only: adopt PostgreSQL's records when ClickHouse has tables but no
    # migration bookkeeping at all. A no-op on every normal boot.
    python -u manage.py sync_clickhouse_migrations
    python -u manage.py migrate --database=clickhouse_write
fi

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
