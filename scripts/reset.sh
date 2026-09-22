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
SEQR_REFERENCE_DATA_DUMP="${SEQR_REFERENCE_DATA_DUMP:-$(env_file_value SEQR_REFERENCE_DATA_DUMP)}"

# Defaults to the user shipped in the local Keycloak realm
# (data/keycloak/realm-seqr.json), so a clean checkout ends up with a Django account that
# the realm's `tester` identity can actually sign in to. Override in .env when pointing
# at the MCRI realm, where the address must be the one that provider asserts.
SEQR_TEST_USER_EMAIL="${SEQR_TEST_USER_EMAIL:-tester@seqr.local}"
SEQR_TEST_PROJECT_NAME="${SEQR_TEST_PROJECT_NAME:-Test Project}"
SEQR_TEST_PROJECT_GENOME_VERSION="${SEQR_TEST_PROJECT_GENOME_VERSION:-38}"

# pg_dump custom-format dump of reference_data_db (gene/transcript/OMIM/HPO reference
# data). Defaults to the newest reference_data_db*.Fc in the repo root, so dropping a
# fresher dump in beside the old one picks it up without editing anything. `ls -t` rather
# than a bare glob because more than one vintage tends to accumulate.
if [ -z "$SEQR_REFERENCE_DATA_DUMP" ];
then
    SEQR_REFERENCE_DATA_DUMP="$(ls -t reference_data_db*.Fc 2>/dev/null | head -n 1)"
fi

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
# Only the per-genome store trees are removed. The sibling pipeline-data/ directory is the
# loading pipeline's own area -- it holds the run parquet that load_to_clickhouse.py reads,
# which is expensive to regenerate -- and is deliberately left alone.
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

# Poll rather than sleep: on a wiped data directory the entrypoint has to run initdb and
# then data/postgres_init/initdb.sql before the real server exists, which takes far longer
# than the fixed 5s this used to wait. The restore below connects immediately, so losing
# that race aborts it.
#
# Specifically this waits on the compose HEALTHCHECK, not on `pg_isready` over the local
# socket, and the difference is not cosmetic. To run the initdb.d scripts the postgres
# entrypoint first starts a TEMPORARY server that listens on the unix socket ONLY, then
# shuts it down and starts the real one:
#
#   [61] listening on Unix socket ".../.s.PGSQL.5432"      <- no TCP listener
#   [61] database system is ready to accept connections    <- socket pg_isready says READY
#        running /docker-entrypoint-initdb.d/initdb.sql
#   [62] shutting down                                     <- any live connection dies here
#   [1]  listening on IPv4 address "0.0.0.0", port 5432    <- real server
#
# A socket probe cannot tell those two apart, so it returns ready during the bootstrap
# window and the restore then dies mid-COPY with "server closed the connection
# unexpectedly". The healthcheck runs `pg_isready -h postgres`, which goes over TCP and
# therefore only succeeds against the real server. Keep it that way.
postgres_ready=
for _ in $(seq 1 90);
do
    postgres_container="$(docker compose ps -q postgres)"
    if [ -n "$postgres_container" ] && \
       [ "$(docker inspect -f '{{.State.Health.Status}}' "$postgres_container" 2>/dev/null)" = "healthy" ];
    then
        postgres_ready=yes
        break
    fi
    sleep 2
done

if [ -z "$postgres_ready" ];
then
    echo "postgres did not become healthy within 3 minutes - see 'docker compose logs postgres'."
fi

# Reference data (genes, transcripts, OMIM, HPO) lives in its own database and is NOT
# recreated by seqr's migrations -- those only build empty tables. Without it the
# ClickHouse `seqrdb_gene_ids` dictionary, which sources from reference_data_geneinfo,
# loads zero rows. That failure is completely silent: every geneId_ids array on every
# loaded variant comes out empty and gene/panel-scoped search returns nothing, with no
# error anywhere. Restoring here is much faster than `manage.py update_all_reference_data`,
# which re-downloads GENCODE and friends.
#
# Deliberately BEFORE seqr starts. seqr's entrypoint runs the migrations that CREATE the
# dictionary, and a ClickHouse dictionary declared LIFETIME(MIN 0 MAX 0) populates once at
# creation and never refreshes on its own. Restoring first means it is created against a
# populated table; restoring afterwards would need an explicit SYSTEM RELOAD DICTIONARY.
if [ -z "$postgres_ready" ];
then
    echo "Skipping reference data restore: postgres is not accepting connections."
elif [ -z "$SEQR_REFERENCE_DATA_DUMP" ];
then
    cat <<EOF

Skipping reference data restore: no reference_data_db*.Fc dump found in $(pwd).

Gene-based search will silently return nothing until reference data is loaded. Either
drop a dump in beside this checkout, point SEQR_REFERENCE_DATA_DUMP at one, or populate
it the slow way once seqr is up:

    docker compose exec seqr python manage.py update_all_reference_data

EOF
elif [ ! -r "$SEQR_REFERENCE_DATA_DUMP" ];
then
    echo "Skipping reference data restore: cannot read '$SEQR_REFERENCE_DATA_DUMP'."
else
    echo
    echo "Restoring reference data from $SEQR_REFERENCE_DATA_DUMP ..."
    echo
    # --clean --if-exists so a re-run over an already-populated database replaces it
    # rather than colliding; --no-owner --no-privileges because the dump was taken as a
    # different role than the local `postgres` superuser.
    if docker compose exec -T postgres pg_restore -U postgres -d reference_data_db \
        --clean --if-exists --no-owner --no-privileges < "$SEQR_REFERENCE_DATA_DUMP";
    then
        gene_count="$(docker compose exec -T postgres psql -U postgres -d reference_data_db \
            -tAc 'select count(*) from reference_data_geneinfo' 2>/dev/null | tr -d '[:space:]')"
        echo "Reference data restored - reference_data_geneinfo has ${gene_count:-?} rows."
    else
        echo "Reference data restore FAILED - gene-based search will return nothing."
        echo "Check 'docker compose logs postgres' for what the server said. Two usual causes:"
        echo "  - 'unsupported version (1.N) in file header': the dump was written by a newer"
        echo "    pg_dump than this server's pg_restore can read."
        echo "  - 'server closed the connection unexpectedly': the server went away mid-restore,"
        echo "    which means it was still starting up and the readiness wait above is wrong."
    fi
fi

echo
echo "Starting keycloak ..."
echo

# Keycloak's database lives in the postgres instance wiped above, so this re-imports
# data/keycloak/realm-seqr.json from scratch -- including a freshly generated realm
# signing key, which the seqr entrypoint fetches at boot. Pulls in keycloak-db-init
# (which recreates the `keycloak` database) through depends_on.
docker compose up -d keycloak

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
