#!/bin/bash

# Activate uv environment
source ~/work/tools/uv/environments/seqr/bin/activate

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"

# Set environment variables
export DJANGO_SETTINGS_MODULE=settings
export PYTHONPATH="$PROJECT_DIR"

# Database connections (from docker-compose)
export POSTGRES_SERVICE_HOSTNAME=localhost
export POSTGRES_SERVICE_PORT=5432
export POSTGRES_USERNAME=postgres
export POSTGRES_PASSWORD=docker-compose-postgres-password

export REDIS_SERVICE_HOSTNAME=localhost
export REDIS_SERVICE_PORT=6379

export CLICKHOUSE_SERVICE_HOSTNAME=localhost
export CLICKHOUSE_SERVICE_PORT=9001
export CLICKHOUSE_WRITER_USER=seqr_user
export CLICKHOUSE_WRITER_PASSWORD=docker-compose-clickhouse-password
export CLICKHOUSE_READER_USER=seqr_user
export CLICKHOUSE_READER_PASSWORD=docker-compose-clickhouse-password
export CLICKHOUSE_DATA_DIR="$PROJECT_DIR/data/clickhouse-seqr-data"
export CLICKHOUSE_IN_MEMORY_DIR="$PROJECT_DIR/data/clickhouse-in-memory"

export ELASTICSEARCH_SERVICE_HOSTNAME=localhost
export ELASTICSEARCH_SERVICE_PORT=9200

export STATIC_MEDIA_DIR="$PROJECT_DIR/data/seqr_static_files"

echo "=========================================="
echo "Seqr development environment activated!"
echo "=========================================="
echo "Project directory: $PROJECT_DIR"
echo ""
echo "Services (via docker-compose):"
echo "  PostgreSQL:     localhost:5433"
echo "  ClickHouse:     localhost:9001"
echo "  ElasticSearch:  localhost:9200"
echo "  Redis:          localhost:6379"
echo ""
echo "To start services:"
echo "  cd $PROJECT_DIR && docker-compose up -d postgres redis clickhouse elasticsearch"
echo ""
echo "To run Django:"
echo "  cd $PROJECT_DIR && python manage.py runserver"
echo "=========================================="
