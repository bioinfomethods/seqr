#!/bin/bash
# Recreate the seqrdb database on Aurora PostgreSQL from a pg_dump backup.
#
# This script:
#   1. Scales down the ECS Fargate service to release database connections
#   2. Waits for all tasks to drain
#   3. Terminates any remaining database connections
#   4. Drops and recreates the seqrdb database
#   5. Restores from a pg_dump custom-format backup
#   6. Scales the ECS Fargate service back up
#
# Prerequisites:
#   - AWS CLI v2 installed and configured
#   - OpenTofu (tofu) installed
#   - psql and pg_restore installed
#   - Run from the deploy/aws directory (or the script will cd there)
#   - Bastion SSH tunnel active on LOCAL_AURORA_PORT (default: 8168)
#
# Usage:
#   ./recreate-database.sh <dump-file> [reference-dump-file]
#
# Examples:
#   # Restore only the main seqrdb database:
#   ./recreate-database.sh /path/to/seqrdb-clean.dump
#
#   # Restore both seqrdb and reference_data_db:
#   ./recreate-database.sh /path/to/seqrdb-clean.dump /path/to/reference_data_db.dump
#
#   LOCAL_AURORA_PORT=5432 DB_USER=seqr ./recreate-database.sh seqrdb.dump reference_data_db.dump

set -euo pipefail

# ---- Configuration (override via environment variables) ----
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${LOCAL_AURORA_PORT:-8168}"
DB_USER="${DB_USER:-seqr}"
DB_NAME="${DB_NAME:-seqrdb}"
REF_DB_NAME="${REF_DB_NAME:-reference_data_db}"
REGION="${AWS_DEFAULT_REGION:-ap-southeast-2}"
DRAIN_TIMEOUT="${DRAIN_TIMEOUT:-120}"  # seconds to wait for ECS tasks to drain

# ---- Arguments ----
DUMP_FILE="${1:-}"
REF_DUMP_FILE="${2:-}"

if [ -z "$DUMP_FILE" ]; then
  echo "Usage: $0 <dump-file> [reference-dump-file]"
  echo ""
  echo "  dump-file:           Path to a pg_dump custom-format backup of seqrdb"
  echo "  reference-dump-file: Path to a pg_dump custom-format backup of reference_data_db (optional)"
  echo ""
  echo "Environment variables:"
  echo "  DB_HOST              Database host (default: localhost)"
  echo "  LOCAL_AURORA_PORT    Database port (default: 8168)"
  echo "  DB_USER              Database user (default: seqr)"
  echo "  DB_NAME              Main database name (default: seqrdb)"
  echo "  REF_DB_NAME          Reference database name (default: reference_data_db)"
  echo "  AWS_DEFAULT_REGION   AWS region (default: ap-southeast-2)"
  echo "  DRAIN_TIMEOUT        Seconds to wait for ECS drain (default: 120)"
  exit 1
fi

if [ ! -f "$DUMP_FILE" ]; then
  echo "Error: Dump file not found: $DUMP_FILE"
  exit 1
fi

# Resolve to absolute path before changing directory
DUMP_FILE="$(cd "$(dirname "$DUMP_FILE")" && pwd)/$(basename "$DUMP_FILE")"

if [ -n "$REF_DUMP_FILE" ]; then
  if [ ! -f "$REF_DUMP_FILE" ]; then
    echo "Error: Reference dump file not found: $REF_DUMP_FILE"
    exit 1
  fi
  REF_DUMP_FILE="$(cd "$(dirname "$REF_DUMP_FILE")" && pwd)/$(basename "$REF_DUMP_FILE")"
fi

# ---- Change to deploy/aws directory for tofu outputs ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
cd "$DEPLOY_DIR"

# ---- Resolve database password from terraform.tfvars or prompt ----
if [ -z "${PGPASSWORD:-}" ]; then
  TFVARS_FILE="${DEPLOY_DIR}/terraform.tfvars"
  if [ -f "$TFVARS_FILE" ]; then
    EXTRACTED_PW=$(grep -E '^\s*aurora_master_password\s*=' "$TFVARS_FILE" \
      | sed -E 's/^[^"]*"([^"]*)".*/\1/' 2>/dev/null) || true
    if [ -n "${EXTRACTED_PW:-}" ]; then
      echo "==> Using aurora_master_password from terraform.tfvars"
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

# ---- Retrieve ECS cluster and service names ----
echo "==> Retrieving ECS cluster and service from Terraform outputs..."
ECS_CLUSTER=$(tofu output -raw ecs_cluster_name)
ECS_SERVICE=$(tofu output -raw ecs_service_name)
echo "    Cluster: ${ECS_CLUSTER}"
echo "    Service: ${ECS_SERVICE}"

# ---- Step 1: Scale down ECS service ----
echo ""
echo "==> Scaling down ECS service to 0..."
aws ecs update-service \
  --cluster "$ECS_CLUSTER" \
  --service "$ECS_SERVICE" \
  --desired-count 0 \
  --region "$REGION" \
  --no-cli-pager \
  > /dev/null

echo "    Waiting for tasks to drain (up to ${DRAIN_TIMEOUT}s)..."
ELAPSED=0
while [ "$ELAPSED" -lt "$DRAIN_TIMEOUT" ]; do
  RUNNING=$(aws ecs list-tasks \
    --cluster "$ECS_CLUSTER" \
    --service-name "$ECS_SERVICE" \
    --desired-status RUNNING \
    --region "$REGION" \
    --output text \
    --query 'taskArns | length(@)' 2>/dev/null) || RUNNING="0"

  if [ "$RUNNING" -eq 0 ]; then
    echo "    ✓ All tasks drained"
    break
  fi

  echo "    Still ${RUNNING} task(s) running... (${ELAPSED}s elapsed)"
  sleep 10
  ELAPSED=$((ELAPSED + 10))
done

if [ "$ELAPSED" -ge "$DRAIN_TIMEOUT" ]; then
  echo "    Warning: Drain timeout reached, proceeding anyway"
fi

# ---- Step 2: Terminate remaining database connections ----
echo ""
echo "==> Terminating remaining connections to ${DB_NAME}..."
psql --host "$DB_HOST" --port "$DB_PORT" --user "$DB_USER" --dbname postgres \
  --no-psqlrc -q -c \
  "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${DB_NAME}' AND pid <> pg_backend_pid();" \
  > /dev/null 2>&1 || true

if [ -n "$REF_DUMP_FILE" ]; then
  echo "==> Terminating remaining connections to ${REF_DB_NAME}..."
  psql --host "$DB_HOST" --port "$DB_PORT" --user "$DB_USER" --dbname postgres \
    --no-psqlrc -q -c \
    "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${REF_DB_NAME}' AND pid <> pg_backend_pid();" \
    > /dev/null 2>&1 || true
fi

# ---- Step 3: Drop and recreate database(s) ----
echo "==> Dropping database ${DB_NAME}..."
psql --host "$DB_HOST" --port "$DB_PORT" --user "$DB_USER" --dbname postgres \
  --no-psqlrc -c "DROP DATABASE IF EXISTS ${DB_NAME};"

echo "==> Creating database ${DB_NAME}..."
psql --host "$DB_HOST" --port "$DB_PORT" --user "$DB_USER" --dbname postgres \
  --no-psqlrc -c "CREATE DATABASE ${DB_NAME};"

if [ -n "$REF_DUMP_FILE" ]; then
  echo "==> Dropping database ${REF_DB_NAME}..."
  psql --host "$DB_HOST" --port "$DB_PORT" --user "$DB_USER" --dbname postgres \
    --no-psqlrc -c "DROP DATABASE IF EXISTS ${REF_DB_NAME};"

  echo "==> Creating database ${REF_DB_NAME}..."
  psql --host "$DB_HOST" --port "$DB_PORT" --user "$DB_USER" --dbname postgres \
    --no-psqlrc -c "CREATE DATABASE ${REF_DB_NAME};"
fi

# ---- Step 4: Restore from backup ----
echo ""
echo "==> Restoring ${DB_NAME} from ${DUMP_FILE}..."
echo "    This may take a while depending on database size..."
pg_restore --no-owner --no-privileges \
  --host "$DB_HOST" --port "$DB_PORT" --user "$DB_USER" --dbname "$DB_NAME" \
  "$DUMP_FILE"

echo "    ✓ ${DB_NAME} restore complete"

if [ -n "$REF_DUMP_FILE" ]; then
  echo ""
  echo "==> Restoring ${REF_DB_NAME} from ${REF_DUMP_FILE}..."
  echo "    This may take a while depending on database size..."
  pg_restore --no-owner --no-privileges \
    --host "$DB_HOST" --port "$DB_PORT" --user "$DB_USER" --dbname "$REF_DB_NAME" \
    "$REF_DUMP_FILE"

  echo "    ✓ ${REF_DB_NAME} restore complete"
fi

# ---- Step 5: Scale ECS service back up ----
echo ""
echo "==> Scaling ECS service back up to 1..."
aws ecs update-service \
  --cluster "$ECS_CLUSTER" \
  --service "$ECS_SERVICE" \
  --desired-count 1 \
  --region "$REGION" \
  --no-cli-pager \
  > /dev/null

echo "    ✓ Service scaling up"

# ---- Done ----
echo ""
echo "==> Database recreation complete!"
echo "    Database: ${DB_NAME} (restored from: ${DUMP_FILE})"
if [ -n "$REF_DUMP_FILE" ]; then
  echo "    Database: ${REF_DB_NAME} (restored from: ${REF_DUMP_FILE})"
fi
echo "    ECS service is starting back up — check ALB health checks in a few minutes."
