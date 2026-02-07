#!/bin/bash
set -e

CLICKHOUSE_DIR="/home/ec2-user/clickhouse"

echo "Starting Clickhouse via docker compose..."
cd "$CLICKHOUSE_DIR"
docker compose up -d

echo "Clickhouse started successfully"
