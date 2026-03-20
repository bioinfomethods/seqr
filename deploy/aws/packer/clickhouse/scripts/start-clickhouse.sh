#!/bin/bash
set -e

# Source environment variables set by EC2 user_data
if [ -f /etc/environment ]; then
    set -a
    source /etc/environment
    set +a
fi

CLICKHOUSE_DIR="/home/ec2-user/clickhouse"
MOUNT_POINT="/var/lib/clickhouse"

# --- Mount dedicated ClickHouse data volume (if configured) ---
DATA_DEVICE="${CLICKHOUSE_DATA_DEVICE:-}"
if [ -n "$DATA_DEVICE" ]; then
    echo "Mounting ClickHouse data volume..."

    # Wait for the EBS volume to be attached (up to 60 seconds)
    for i in $(seq 1 60); do
        [ -b "$DATA_DEVICE" ] && break
        echo "  Waiting for $DATA_DEVICE to appear... ($i/60)"
        sleep 1
    done

    if [ -b "$DATA_DEVICE" ]; then
        # Format only if no filesystem exists (preserves data on reboot/restore from snapshot)
        if ! blkid "$DATA_DEVICE" | grep -q TYPE; then
            echo "  Formatting $DATA_DEVICE as ext4..."
            mkfs.ext4 -m 0 "$DATA_DEVICE"
        fi

        # Ensure mount point exists
        mkdir -p "$MOUNT_POINT"

        # Add to fstab for persistence across reboots (if not already present)
        if ! grep -q "$MOUNT_POINT" /etc/fstab; then
            echo "$DATA_DEVICE $MOUNT_POINT ext4 defaults,nofail 0 2" >> /etc/fstab
        fi

        # Mount the volume
        if ! mountpoint -q "$MOUNT_POINT"; then
            mount "$MOUNT_POINT"
        fi

        # Set ownership for ClickHouse container (UID 101:101 in official ClickHouse images)
        chown -R 101:101 "$MOUNT_POINT"
        echo "  ✓ Data volume mounted at $MOUNT_POINT"
    else
        echo "  WARNING: Data volume $DATA_DEVICE not found after 60s. Using root volume."
    fi
else
    echo "No CLICKHOUSE_DATA_DEVICE configured, using default storage."
fi

# --- Configure PostgreSQL named collection ---
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

# --- Start ClickHouse ---
echo "Starting Clickhouse via docker compose..."
cd "$CLICKHOUSE_DIR"
docker compose up -d

echo "Clickhouse started successfully"
