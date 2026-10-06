#!/bin/bash
# Back up the seqrdb and reference_data_db databases on RDS PostgreSQL with pg_dump.
#
# Produces pg_dump custom-format files that recreate-database.sh restores in place
# into the existing RDS instance. This is preferred over RDS snapshots for dev resets:
# an RDS snapshot can only be restored to a NEW instance with a new endpoint, which
# does not match the Terraform-managed instance that ECS and ClickHouse point at.
#
# The service does not need to be stopped. pg_dump reads a consistent snapshot of
# each database even while seqr is running.
#
# Dumps contain patient data. They are written outside the repository by default,
# with owner-only permissions.
#
# Prerequisites:
#   - pg_dump, pg_restore and psql installed, with a pg_dump major version >= the
#     server's (RDS runs PostgreSQL 17)
#   - Bastion SSH tunnel active on LOCAL_DB_PORT (default: 8168)
#
# Usage:
#   ./backup-database.sh [label]
#
# Examples:
#   ./backup-database.sh
#   ./backup-database.sh post-migrate-clean
#   BACKUP_DIR=/mnt/backups ./backup-database.sh

set -euo pipefail

# ---- Configuration (override via environment variables) ----
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${LOCAL_DB_PORT:-8168}"
DB_USER="${DB_USER:-seqr}"
DB_NAME="${DB_NAME:-seqrdb}"
REF_DB_NAME="${REF_DB_NAME:-reference_data_db}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/seqr-backups}"

# ---- Arguments ----
LABEL="${1:-}"
if [[ ! "$LABEL" =~ ^[A-Za-z0-9._-]*$ ]]; then
  echo "Error: label may only contain letters, digits, '.', '_' and '-'"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"

# ---- Resolve database password from terraform.tfvars or prompt ----
if [ -z "${PGPASSWORD:-}" ]; then
  TFVARS_FILE="${DEPLOY_DIR}/terraform.tfvars"
  if [ -f "$TFVARS_FILE" ]; then
    EXTRACTED_PW=$(grep -E '^\s*db_master_password\s*=' "$TFVARS_FILE" \
      | sed -E 's/^[^"]*"([^"]*)".*/\1/' 2>/dev/null) || true
    if [ -n "${EXTRACTED_PW:-}" ]; then
      echo "==> Using db_master_password from terraform.tfvars"
      PGPASSWORD="$EXTRACTED_PW"
    fi
  fi
  if [ -z "${PGPASSWORD:-}" ]; then
    echo -n "==> Enter password for PostgreSQL user '${DB_USER}': "
    read -rs PGPASSWORD
    echo ""
  fi
  export PGPASSWORD
fi

# ---- Check connectivity and client/server version compatibility ----
echo "==> Connecting to ${DB_HOST}:${DB_PORT}..."
SERVER_VERSION_NUM=$(psql --host "$DB_HOST" --port "$DB_PORT" --user "$DB_USER" --dbname postgres \
  --no-psqlrc -tAc 'SHOW server_version_num') || {
  echo "Error: could not connect. Is the bastion tunnel up on port ${DB_PORT}?"
  exit 1
}
SERVER_MAJOR=$((SERVER_VERSION_NUM / 10000))
CLIENT_MAJOR=$(pg_dump --version | awk '{print $3}' | cut -d. -f1)
echo "    Server PostgreSQL ${SERVER_MAJOR}, pg_dump ${CLIENT_MAJOR}"
if [ "$CLIENT_MAJOR" -lt "$SERVER_MAJOR" ]; then
  echo "Error: pg_dump ${CLIENT_MAJOR} cannot dump a PostgreSQL ${SERVER_MAJOR} server."
  echo "       Install a PostgreSQL ${SERVER_MAJOR}+ client and retry."
  exit 1
fi

# ---- Prepare output ----
umask 077
mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
SUFFIX="${TIMESTAMP}${LABEL:+-$LABEL}"
PG_FILE="${BACKUP_DIR}/${DB_NAME}-${SUFFIX}.dump"
REF_FILE="${BACKUP_DIR}/${REF_DB_NAME}-${SUFFIX}.dump"

# Remove any half-written dump if the script fails or is interrupted.
CURRENT_PARTIAL=""
cleanup() {
  if [ -n "$CURRENT_PARTIAL" ]; then
    rm -f "$CURRENT_PARTIAL"
  fi
}
trap cleanup EXIT

dump_database() {
  local db="$1" out="$2"
  CURRENT_PARTIAL="${out}.partial"
  echo ""
  echo "==> Dumping ${db} to ${out}..."
  pg_dump --format=custom \
    --host "$DB_HOST" --port "$DB_PORT" --user "$DB_USER" --dbname "$db" \
    --file "$CURRENT_PARTIAL"
  # Confirm the archive is readable before treating it as a usable backup.
  pg_restore --list "$CURRENT_PARTIAL" > /dev/null
  mv "$CURRENT_PARTIAL" "$out"
  CURRENT_PARTIAL=""
  echo "    ✓ ${db} ($(du -h "$out" | cut -f1))"
}

dump_database "$DB_NAME" "$PG_FILE"
dump_database "$REF_DB_NAME" "$REF_FILE"

# ---- Done ----
echo ""
echo "==> Backup complete"
echo "    ${PG_FILE}"
echo "    ${REF_FILE}"
echo ""
echo "    To restore (run from deploy/aws):"
echo "    ./scripts/recreate-database.sh \"${PG_FILE}\" \"${REF_FILE}\""
