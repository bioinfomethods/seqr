#!/usr/bin/env bash
set -euo pipefail

echo
echo "Make sure you already ran the bastion port forward script ..."
echo

# Configuration
CH_HOST="${CH_HOST:-localhost}"
CH_PORT="${CH_PORT:-8169}"
CH_USER="${CH_USER:-default}"
CH_DATABASE="${CH_DATABASE:-seqr}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${1:-clickhouse_dump_${TIMESTAMP}}"

echo "=== ClickHouse Database Dump ==="
echo "Host:      ${CH_HOST}:${CH_PORT}"
echo "Database:  ${CH_DATABASE}"
echo "Output:    ${BACKUP_DIR}"
echo

# Helper function for clickhouse-client calls
ch() {
  clickhouse client --host "$CH_HOST" --port "$CH_PORT" --user "$CH_USER" --database "$CH_DATABASE" "$@"
}

# Check connectivity
if ! ch --query "SELECT 1" >/dev/null 2>&1; then
  echo "ERROR: Cannot connect to ClickHouse at ${CH_HOST}:${CH_PORT}"
  echo "Make sure the bastion port forward is running."
  exit 1
fi

mkdir -p "${BACKUP_DIR}/schema" "${BACKUP_DIR}/data"

# Get all tables (excluding system tables)
echo "Discovering tables..."
TABLES=$(ch --query "SELECT name FROM system.tables WHERE database = '${CH_DATABASE}' ORDER BY name" --format TSVRaw)

if [ -z "$TABLES" ]; then
  echo "ERROR: No tables found in database '${CH_DATABASE}'"
  exit 1
fi

TABLE_COUNT=$(echo "$TABLES" | wc -l | tr -d ' ')
echo "Found ${TABLE_COUNT} tables"
echo

# Dump schema for all tables
echo "--- Dumping schema ---"
while IFS= read -r table; do
  # Replace / with __ for safe filenames
  safe_name="${table//\//__}"
  echo "  Schema: ${table}"
  ch --query "SHOW CREATE TABLE \`${table}\`" > "${BACKUP_DIR}/schema/${safe_name}.sql" 2>/dev/null || {
    echo "    WARNING: Failed to dump schema for ${table}, skipping"
    rm -f "${BACKUP_DIR}/schema/${safe_name}.sql"
  }
done <<< "$TABLES"
echo

# Dump data for tables that hold data (skip materialized views)
echo "--- Dumping data ---"
while IFS= read -r table; do
  safe_name="${table//\//__}"

  # Get the engine type to decide how to handle the table
  engine=$(ch --query "SELECT engine FROM system.tables WHERE database = '${CH_DATABASE}' AND name = '${table}'" --format TSVRaw 2>/dev/null)

  # Skip materialized views - they are just triggers, no data to dump
  if [[ "$engine" == *"MaterializedView"* ]]; then
    echo "  Skip (MaterializedView): ${table}"
    continue
  fi

  # Get row count
  row_count=$(ch --query "SELECT count() FROM \`${table}\`" --format TSVRaw 2>/dev/null) || row_count="?"

  if [ "$row_count" = "0" ]; then
    echo "  Skip (empty): ${table}"
    continue
  fi

  echo "  Data: ${table} (${row_count} rows, ${engine})"
  ch --query "SELECT * FROM \`${table}\` FORMAT Native" > "${BACKUP_DIR}/data/${safe_name}.native" 2>/dev/null || {
    echo "    WARNING: Failed to dump data for ${table} (engine: ${engine}), skipping"
    rm -f "${BACKUP_DIR}/data/${safe_name}.native"
  }
done <<< "$TABLES"
echo

# Write metadata
cat > "${BACKUP_DIR}/metadata.txt" <<EOF
Database: ${CH_DATABASE}
Timestamp: ${TIMESTAMP}
Host: ${CH_HOST}:${CH_PORT}
Tables: ${TABLE_COUNT}
ClickHouse Server Version: $(ch --query "SELECT version()" --format TSVRaw 2>/dev/null || echo "unknown")
EOF

# Summary
SCHEMA_COUNT=$(ls -1 "${BACKUP_DIR}/schema/"*.sql 2>/dev/null | wc -l | tr -d ' ')
DATA_COUNT=$(ls -1 "${BACKUP_DIR}/data/"*.native 2>/dev/null | wc -l | tr -d ' ')
TOTAL_SIZE=$(du -sh "${BACKUP_DIR}" | cut -f1)

echo "=== Dump Complete ==="
echo "Schema files: ${SCHEMA_COUNT}"
echo "Data files:   ${DATA_COUNT}"
echo "Total size:   ${TOTAL_SIZE}"
echo "Location:     ${BACKUP_DIR}"
echo
echo "To restore, run: deploy/aws/scripts/clickhouse_restore.sh ${BACKUP_DIR}"
