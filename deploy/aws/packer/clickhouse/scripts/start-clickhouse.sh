#!/bin/bash
set -e

echo "Starting Clickhouse container..."

# Stop and remove existing container if it exists
docker stop clickhouse-server 2>/dev/null || true
docker rm clickhouse-server 2>/dev/null || true

# Run Clickhouse container
docker run -d \
  --name clickhouse-server \
  --restart unless-stopped \
  -p 8123:8123 \
  -p 9000:9000 \
  -v /var/lib/clickhouse:/var/lib/clickhouse \
  -v /opt/clickhouse/config/config.xml:/etc/clickhouse-server/config.d/config.xml \
  -v /opt/clickhouse/config/users.xml:/etc/clickhouse-server/users.d/users.xml \
  -v /opt/clickhouse/config/named_collections.xml:/etc/clickhouse-server/config.d/named_collections.xml \
  -v /opt/clickhouse/config/init-permissions.sql:/docker-entrypoint-initdb.d/init-permissions.sql \
  clickhouse/clickhouse-server:25.12

echo "Clickhouse container started successfully"
