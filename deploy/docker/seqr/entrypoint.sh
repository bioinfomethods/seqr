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

# Run a command that must succeed for seqr to be safe to start. ClickHouse DDL is not
# transactional, so a migration that fails part-way leaves objects behind and is not
# recorded. Starting gunicorn anyway would serve searches against a half-migrated
# database, and the original error would be buried by "already exists" on every later
# boot. Exiting instead makes ECS stop the task (seqr-web is essential), so the failure
# is visible as a failed deployment rather than as quietly wrong results.
run_required() {
    if ! "$@"; then
        echo "FATAL: '$*' failed - refusing to start seqr with a partially migrated database" >&2
        exit 1
    fi
}

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

# Resolve the Keycloak realm signing key if it was not supplied.
#
# social_core's KeycloakOAuth2 verifies every access token against
# SOCIAL_AUTH_KEYCLOAK_PUBLIC_KEY, the realm's RSA public key as bare base64. A hosted
# realm has a stable key that can simply be set in the environment. The local dev realm
# is created by `--import-realm` and generates a fresh keypair each time it is built, so
# no static default can ever be correct -- and a wrong key fails at login with an opaque
# signature error rather than at boot.
#
# /realms/<name> exposes `public_key` in exactly the format the setting expects. This
# only runs when the key is absent, so deployments that set it explicitly are untouched
# and never depend on the identity provider being reachable at startup.
if [ -z "$SOCIAL_AUTH_KEYCLOAK_PUBLIC_KEY" ] && [ -n "$SOCIAL_AUTH_INTERNAL_API_URL" ]; then
    echo "SOCIAL_AUTH_KEYCLOAK_PUBLIC_KEY is unset - fetching it from $SOCIAL_AUTH_INTERNAL_API_URL"
    for kc_attempt in $(seq 1 30); do
        kc_public_key=$(curl -sf "$SOCIAL_AUTH_INTERNAL_API_URL" \
            | python -c 'import sys, json; print(json.load(sys.stdin)["public_key"])' 2>/dev/null)
        if [ -n "$kc_public_key" ]; then
            export SOCIAL_AUTH_KEYCLOAK_PUBLIC_KEY="$kc_public_key"
            echo "Fetched realm public key (${#kc_public_key} chars)"
            break
        fi
        echo "Keycloak realm not ready, retrying (${kc_attempt}/30)"
        sleep 4
    done
    if [ -z "$SOCIAL_AUTH_KEYCLOAK_PUBLIC_KEY" ]; then
        echo "WARNING: could not fetch the Keycloak realm public key from" \
             "$SOCIAL_AUTH_INTERNAL_API_URL - OIDC login will fail with a signature error"
    fi
fi

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
run_required python -u manage.py migrate
run_required python -u manage.py migrate --database=reference_data
if [ "$CLICKHOUSE_SERVICE_HOSTNAME" ]; then
    # Legacy repair only: adopt PostgreSQL's records when ClickHouse has tables but no
    # migration bookkeeping at all. A no-op on every normal boot.
    run_required python -u manage.py sync_clickhouse_migrations
    run_required python -u manage.py migrate --database=clickhouse_write
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
