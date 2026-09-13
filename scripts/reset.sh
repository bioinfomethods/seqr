#!/bin/bash

echo
echo "Seqr Clickhoust Reset Script"
echo

# Run from the repo root regardless of where the script was invoked from, so the
# relative paths below (data/postgres, ui/dist, .env) resolve consistently.
cd "$(dirname "$0")/.." || exit 1

# Seed configuration. docker compose reads .env by itself for its own variable
# substitution, but this script's shell does not, so read the values here too.
# SEQR_TEST_USER_EMAIL must match the address the OIDC identity provider asserts.
#
# Deliberately parsed rather than sourced. A compose .env is not a shell script: it
# allows unquoted values containing spaces, so `. ./.env` on a line like
#   SEQR_TEST_PROJECT_NAME=Functional Test Project
# assigns only "Functional" and then tries to run "Test" as a command. Sourcing would
# also execute whatever else the file happens to contain.
env_file_value() {
    [ -f .env ] || return 0
    sed -n "s/^[[:space:]]*$1[[:space:]]*=//p" .env \
        | tail -n 1 \
        | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/"
}

# An exported variable wins over the .env file, matching how compose resolves these.
SEQR_TEST_USER_EMAIL="${SEQR_TEST_USER_EMAIL:-$(env_file_value SEQR_TEST_USER_EMAIL)}"
SEQR_TEST_PROJECT_NAME="${SEQR_TEST_PROJECT_NAME:-$(env_file_value SEQR_TEST_PROJECT_NAME)}"
SEQR_TEST_PROJECT_GENOME_VERSION="${SEQR_TEST_PROJECT_GENOME_VERSION:-$(env_file_value SEQR_TEST_PROJECT_GENOME_VERSION)}"

SEQR_TEST_PROJECT_NAME="${SEQR_TEST_PROJECT_NAME:-Test Project}"
SEQR_TEST_PROJECT_GENOME_VERSION="${SEQR_TEST_PROJECT_GENOME_VERSION:-38}"

docker compose down

rm -rf data/postgres

docker volume rm  seqrc-test_clickhouse-data
docker volume rm seqrc-test_clickhouse-in-memory

# The two volumes above are only half of ClickHouse's state. The `*_disk` tables
# (annotations/key_lookup/transcripts) are EmbeddedRocksDB stores whose backing files
# live under CLICKHOUSE_DATA_DIR, which is the ./data/clickhouse-seqr-data bind mount --
# not in either volume. Dropping the metadata volume without these leaves migration 0015
# issuing CREATE TABLE ... ENGINE = EmbeddedRocksDB against a store that is already on
# disk. If that store was left mid-write (the container stopped while the table was being
# created) its MANIFEST is truncated, and every later reset dies with
#   Code: 555. Failed to open rocksdb path at: .../annotations:
#   Corruption: no log_file_number, next_file_number, last_sequence entry in MANIFEST
# which no amount of re-resetting clears. Remove the stores so the reset is a real reset.
#
# Only the per-genome store trees are removed. pipeline-data is the loading pipeline's
# own area (./data/runs is bind mounted inside it) and is deliberately left alone.
for genome_dir in data/clickhouse-seqr-data/GRCh37 data/clickhouse-seqr-data/GRCh38;
do
    if [ -e "$genome_dir" ];
    then
        echo "Removing ClickHouse RocksDB stores under $genome_dir"
        rm -rf "$genome_dir"
    fi
done

echo
echo "Starting postgres ..."
echo

docker compose up -d postgres redis

sleep 5

echo
echo "Starting clickhouse  ..."
echo
docker compose up -d clickhouse

sleep 5

if [ ! -e ui/dist ];
then
    nvm use || { echo "Please install nvm" ; exit 1; }

    echo "Building ui assets ..."
    echo
    (cd ui && npm ci && npm run build)
fi


echo
echo "Starting seqr ..."
echo

docker compose up -d --build seqr

echo
echo "Waiting for seqr to finish migrations and start serving ..."
echo

# The seqr container runs migrations in its entrypoint before gunicorn starts, and a
# from-scratch run of those takes several minutes. Poll the healthcheck rather than
# sleeping a fixed amount, so the seeding below never races the migrations.
# docker inspect rather than `docker compose ps --format '{{.Health}}'`: the ps
# template field is not available on every compose version, and there it yields an
# empty string, which would look like "never healthy" and silently skip seeding.
seqr_ready=
for _ in $(seq 1 120);
do
    seqr_container="$(docker compose ps -q seqr)"
    if [ -n "$seqr_container" ] && \
       [ "$(docker inspect -f '{{.State.Health.Status}}' "$seqr_container" 2>/dev/null)" = "healthy" ];
    then
        seqr_ready=yes
        break
    fi
    sleep 10
done

if [ -z "$seqr_ready" ];
then
    echo "seqr did not become healthy within 20 minutes - skipping seeding."
    echo "Check 'docker compose logs seqr' for what went wrong."
elif [ -z "$SEQR_TEST_USER_EMAIL" ];
then
    cat <<EOF

Skipping user and project seeding: SEQR_TEST_USER_EMAIL is not set.

seqr signs users in through OIDC, and the login pipeline only associates an external
identity with a Django account that already exists and carries the same email address.
So the account has to be seeded here before that identity can log in at all.

To seed it, add the email of your external identity to .env:

    echo 'SEQR_TEST_USER_EMAIL=you@example.org' >> .env

Optionally override the project that gets created alongside it:

    SEQR_TEST_PROJECT_NAME=Test Project
    SEQR_TEST_PROJECT_GENOME_VERSION=38     # 37 or 38

Then re-run this script, or seed without a full reset:

    docker compose exec seqr python manage.py bootstrap_dev_data --email you@example.org

EOF
else
    echo
    echo "Seeding user $SEQR_TEST_USER_EMAIL and project \"$SEQR_TEST_PROJECT_NAME\" ..."
    echo
    docker compose exec -T seqr python manage.py bootstrap_dev_data \
        --email "$SEQR_TEST_USER_EMAIL" \
        --project "$SEQR_TEST_PROJECT_NAME" \
        --genome-version "$SEQR_TEST_PROJECT_GENOME_VERSION" \
        || echo "Seeding failed - see the output above."
fi

echo
echo "Adding test family ..."
echo
python manage.py add_families  R0001_functional_test_project ./data/test-data/R0001_functional_test_project_pedigree.tsv 

echo
echo "NOTE: to import data: bash scripts/import_clickhouse_data.sh   --run-id 20260906_03_test --project-guid R0001_functional_test_project  --sample-type WGS  --family-guids F000001_f0001 --remote-host login001.meerkat.mcri.edu.au --remote-path /misc/bioinf-ops/seqr-clickhouse-ingest/pipeline-data"
echo

echo
echo "Log lines follow ..."
echo

docker compose logs --tail 50 --follow 
