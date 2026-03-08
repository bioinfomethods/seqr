#!/bin/bash
set -e

# Source environment variables set by EC2 user_data
if [ -f /etc/environment ]; then
    set -a
    source /etc/environment
    set +a
fi

CLICKHOUSE_DIR="/home/ec2-user/clickhouse"

# Substitute PostgreSQL connection details in named_collections.xml from environment variables.
# These are set via EC2 user_data or /etc/environment.
NAMED_COLLECTIONS="${CLICKHOUSE_DIR}/config/named_collections.xml"
if [ -f "$NAMED_COLLECTIONS" ]; then
    echo "Configuring PostgreSQL named collection..."
    sed -i \
        -e "s|__POSTGRES_HOST__|${POSTGRES_HOST:-postgres}|g" \
        -e "s|__POSTGRES_PORT__|${POSTGRES_PORT:-5432}|g" \
        -e "s|__POSTGRES_USER__|${POSTGRES_USER:-postgres}|g" \
        -e "s|__POSTGRES_PASSWORD__|${POSTGRES_PASSWORD:-}|g" \
        -e "s|__POSTGRES_DATABASE__|${POSTGRES_DATABASE:-seqrdb}|g" \
        "$NAMED_COLLECTIONS"
    echo "  ✓ Named collection configured (host=${POSTGRES_HOST:-postgres}, port=${POSTGRES_PORT:-5432})"
fi

echo "Starting Clickhouse via docker compose..."
cd "$CLICKHOUSE_DIR"
docker compose up -d

echo "Clickhouse started successfully"
