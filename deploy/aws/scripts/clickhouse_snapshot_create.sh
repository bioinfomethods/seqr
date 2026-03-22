#!/bin/bash
set -euo pipefail

# Create an EBS snapshot of the ClickHouse data volume.
# Run from the deploy/aws directory (where Terraform state lives).
#
# Usage:
#   ./scripts/clickhouse_snapshot_create.sh [description]
#
# Examples:
#   ./scripts/clickhouse_snapshot_create.sh "post-migration clean state"
#   ./scripts/clickhouse_snapshot_create.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

DESCRIPTION="${1:-manual snapshot $(date +%Y%m%d-%H%M%S)}"

echo "=== ClickHouse EBS Snapshot ==="
echo

# Get volume ID from Terraform state
echo "Looking up ClickHouse data volume from Terraform state..."
cd "$TF_DIR"

VOLUME_ID=$(terraform output -raw clickhouse_data_volume_id 2>/dev/null || true)
if [ -z "$VOLUME_ID" ]; then
    echo "ERROR: Could not find clickhouse_data_volume_id in Terraform outputs."
    echo "Make sure you're running this from the deploy/aws directory and Terraform has been applied."
    exit 1
fi

INSTANCE_ID=$(terraform output -raw clickhouse_instance_id 2>/dev/null || true)
NAME_PREFIX=$(terraform output -raw name_prefix 2>/dev/null || true)

echo "  Volume ID:   $VOLUME_ID"
echo "  Instance:    ${INSTANCE_ID:-unknown}"
echo "  Description: $DESCRIPTION"
echo

# Create the snapshot
echo "Creating snapshot..."
SNAPSHOT_ID=$(aws ec2 create-snapshot \
    --volume-id "$VOLUME_ID" \
    --description "ClickHouse data: $DESCRIPTION" \
    --tag-specifications "ResourceType=snapshot,Tags=[
        {Key=Name,Value=${NAME_PREFIX:-seqr}-clickhouse-data-snapshot},
        {Key=Description,Value=$(echo "$DESCRIPTION" | tr ' ' '_')},
        {Key=SourceVolumeId,Value=$VOLUME_ID},
        {Key=SourceInstanceId,Value=${INSTANCE_ID:-unknown}},
        {Key=Project,Value=seqr},
        {Key=ManagedBy,Value=script}
    ]" \
    --query 'SnapshotId' \
    --output text)

echo "  Snapshot ID: $SNAPSHOT_ID"
echo

# Wait for snapshot to complete
echo "Waiting for snapshot to complete (this may take several minutes)..."
aws ec2 wait snapshot-completed --snapshot-ids "$SNAPSHOT_ID"

# Get snapshot details
SNAPSHOT_SIZE=$(aws ec2 describe-snapshots \
    --snapshot-ids "$SNAPSHOT_ID" \
    --query 'Snapshots[0].VolumeSize' \
    --output text)

echo
echo "=== Snapshot Complete ==="
echo "  Snapshot ID: $SNAPSHOT_ID"
echo "  Volume Size: ${SNAPSHOT_SIZE} GB"
echo "  Description: $DESCRIPTION"
echo
echo "To restore this snapshot later, run:"
echo "  ./scripts/clickhouse_snapshot_restore.sh $SNAPSHOT_ID"
