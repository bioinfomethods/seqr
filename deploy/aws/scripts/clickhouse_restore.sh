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
BACKUP_DIR="${1:-}"

if [ -z "$BACKUP_DIR" ]; then
  echo "Usage: $0 <backup_directory>"
  echo "Example: $0 clickhouse_dump_20260320_143000"
  exit 1
fi

if [ ! -d "$BACKUP_DIR" ]; then
  echo "ERROR: Backup directory '${BACKUP_DIR}' does not exist"
  exit 1
fi

echo "=== ClickHouse Database Restore ==="
echo "Host:      ${CH_HOST}:${CH_PORT}"
echo "Database:  ${CH_DATABASE}"
echo "Source:    ${BACKUP_DIR}"
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

# Show metadata if available
if [ -f "${BACKUP_DIR}/metadata.txt" ]; then
  echo "--- Backup Metadata ---"
  cat "${BACKUP_DIR}/metadata.txt"
  echo
fi

# Confirm before proceeding
read -p "This will DROP and recreate tables in '${CH_DATABASE}'. Continue? [y/N] " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

echo
echo "--- Creating database if needed ---"
ch --query "CREATE DATABASE IF NOT EXISTS \`${CH_DATABASE}\`" --database "" 2>/dev/null || true

# Categorise schema files by engine type for correct restore order:
#   1. Base tables (MergeTree, EmbeddedRocksDB, Join, etc.)
#   2. Materialized views (depend on base tables)
echo "--- Restoring schema ---"

BASE_TABLES=()
MATERIALIZED_VIEWS=()

for schema_file in "${BACKUP_DIR}/schema/"*.sql; do
  [ -f "$schema_file" ] || continue
  safe_name=$(basename "$schema_file" .sql)
  table="${safe_name//__//}"

  if grep -qi "MATERIALIZED VIEW" "$schema_file"; then
    MATERIALIZED_VIEWS+=("$schema_file")
  else
    BASE_TABLES+=("$schema_file")
  fi
done

# Drop existing tables in reverse order (MVs first, then base tables)
echo "  Dropping existing materialized views..."
for schema_file in "${MATERIALIZED_VIEWS[@]+"${MATERIALIZED_VIEWS[@]}"}"; do
  [ -f "$schema_file" ] || continue
  safe_name=$(basename "$schema_file" .sql)
  table="${safe_name//__//}"
  ch --query "DROP TABLE IF EXISTS \`${table}\`" 2>/dev/null || true
done

echo "  Dropping existing base tables..."
for schema_file in "${BASE_TABLES[@]+"${BASE_TABLES[@]}"}"; do
  [ -f "$schema_file" ] || continue
  safe_name=$(basename "$schema_file" .sql)
  table="${safe_name//__//}"
  ch --query "DROP TABLE IF EXISTS \`${table}\`" 2>/dev/null || true
done

# Create base tables first
echo "  Creating base tables..."
for schema_file in "${BASE_TABLES[@]+"${BASE_TABLES[@]}"}"; do
  [ -f "$schema_file" ] || continue
  safe_name=$(basename "$schema_file" .sql)
  table="${safe_name//__//}"
  echo "    Create: ${table}"
  ch --multiquery < "$schema_file" 2>/dev/null || {
    echo "    WARNING: Failed to create ${table}"
  }
done

# Create materialized views
echo "  Creating materialized views..."
for schema_file in "${MATERIALIZED_VIEWS[@]+"${MATERIALIZED_VIEWS[@]}"}"; do
  [ -f "$schema_file" ] || continue
  safe_name=$(basename "$schema_file" .sql)
  table="${safe_name//__//}"
  echo "    Create: ${table}"
  ch --multiquery < "$schema_file" 2>/dev/null || {
    echo "    WARNING: Failed to create ${table}"
  }
done
echo

# Restore data
echo "--- Restoring data ---"
for data_file in "${BACKUP_DIR}/data/"*.native; do
  [ -f "$data_file" ] || continue
  safe_name=$(basename "$data_file" .native)
  table="${safe_name//__//}"

  file_size=$(du -sh "$data_file" | cut -f1)
  echo "  Data: ${table} (${file_size})"
  ch --query "INSERT INTO \`${table}\` FORMAT Native" < "$data_file" 2>/dev/null || {
    echo "    WARNING: Failed to restore data for ${table}"
  }
done
echo

echo "=== Restore Complete ==="
echo "Verify with: clickhouse client --host ${CH_HOST} --port ${CH_PORT} --query \"SELECT name, total_rows FROM system.tables WHERE database='${CH_DATABASE}' ORDER BY name\""
