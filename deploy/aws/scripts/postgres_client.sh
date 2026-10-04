#!/bin/bash
# Connect to the RDS PostgreSQL database with psql through the bastion SSH tunnel.
#
# Prerequisites:
#   - psql installed locally
#   - Bastion SSH tunnel active (run ./ssh-to-bastion.sh in another terminal),
#     which forwards localhost:LOCAL_DB_PORT (default 8168) to the RDS endpoint
#
# Usage:
#   ./postgres_client.sh [database] [extra psql args...]
#
# Examples:
#   ./postgres_client.sh                                  # interactive session on seqrdb
#   ./postgres_client.sh reference_data_db                # interactive session on reference_data_db
#   ./postgres_client.sh postgres -c "\l"                 # list databases
#   ./postgres_client.sh seqrdb -c "SELECT version();"    # run a single query
#   ./postgres_client.sh -f script.sql                    # run a SQL file against seqrdb
#
# Environment variables:
#   DB_HOST         Database host (default: localhost)
#   LOCAL_DB_PORT   Local tunnel port (default: 8168)
#   DB_USER         Database user (default: seqr)
#   PGPASSWORD      Password (default: db_master_password from terraform.tfvars, else prompt)
#   PGSSLMODE       SSL mode (default: require; RDS enforces SSL via rds.force_ssl)

set -euo pipefail

DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${LOCAL_DB_PORT:-8168}"
DB_USER="${DB_USER:-seqr}"
SSL_MODE="${PGSSLMODE:-require}"

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

# Optional first argument is the database name (unless it looks like a psql flag)
DB_NAME="seqrdb"
if [ $# -gt 0 ] && [[ "$1" != -* ]]; then
  DB_NAME="$1"
  shift
fi

if ! command -v psql >/dev/null 2>&1; then
  echo "Error: psql not found. Install the PostgreSQL client (e.g. 'brew install libpq' on macOS)."
  exit 1
fi

# Check the bastion tunnel is up before prompting for a password
if ! (echo > "/dev/tcp/${DB_HOST}/${DB_PORT}") 2>/dev/null; then
  echo "Error: Cannot connect to ${DB_HOST}:${DB_PORT}"
  echo "       Start the bastion tunnel first in another terminal: ./ssh-to-bastion.sh"
  exit 1
fi

# Resolve password from terraform.tfvars or prompt (do not cd, so relative -f paths still work)
if [ -z "${PGPASSWORD:-}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  TFVARS_FILE="$(dirname "$SCRIPT_DIR")/terraform.tfvars"
  if [ -f "$TFVARS_FILE" ]; then
    EXTRACTED_PW=$(grep -E '^[[:space:]]*db_master_password[[:space:]]*=' "$TFVARS_FILE" \
      | sed -E 's/^[^"]*"([^"]*)".*/\1/' 2>/dev/null) || true
    if [ -n "${EXTRACTED_PW:-}" ]; then
      PGPASSWORD="$EXTRACTED_PW"
    fi
  fi
  if [ -z "${PGPASSWORD:-}" ]; then
    echo -n "Enter password for PostgreSQL user '${DB_USER}': "
    read -rs PGPASSWORD
    echo ""
  fi
  export PGPASSWORD
fi

echo "Connecting to ${DB_NAME} as ${DB_USER} via ${DB_HOST}:${DB_PORT} (sslmode=${SSL_MODE})..." >&2
exec psql "host=${DB_HOST} port=${DB_PORT} user=${DB_USER} dbname=${DB_NAME} sslmode=${SSL_MODE}" "$@"
