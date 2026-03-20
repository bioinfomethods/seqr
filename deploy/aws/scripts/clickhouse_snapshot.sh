#!/usr/bin/env bash
set -euo pipefail

# Snapshot the dedicated ClickHouse data EBS volume.
# Run from your local machine (requires AWS CLI configured with appropriate permissions).

DESCRIPTION="${1:-seqr clickhouse data snapshot}"

echo "=== ClickHouse Data Volume Snapshot ==="
echo

# Find the ClickHouse data volume by tag
VOLUME_ID=$(aws ec2 describe-volumes \
  --filters "Name=tag:Name,Values=*clickhouse-data*" \
  --query "Volumes[0].VolumeId" \
  --output text 2>/dev/null)

if [ -z "$VOLUME_ID" ] || [ "$VOLUME_ID" = "None" ]; then
  echo "ERROR: Could not find ClickHouse data volume."
  echo "Looking for volumes with tag Name matching '*clickhouse-data*'"
  echo
  echo "Available volumes:"
  aws ec2 describe-volumes \
    --query "Volumes[*].{ID:VolumeId,Name:Tags[?Key=='Name'].Value|[0],Size:Size,State:State}" \
    --output table
  exit 1
fi

VOLUME_SIZE=$(aws ec2 describe-volumes \
  --volume-ids "$VOLUME_ID" \
  --query "Volumes[0].Size" \
  --output text)

echo "Volume ID:   ${VOLUME_ID}"
echo "Volume Size: ${VOLUME_SIZE} GB"
echo "Description: ${DESCRIPTION}"
echo

read -p "Create snapshot? [y/N] " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

echo "Creating snapshot..."
SNAPSHOT_ID=$(aws ec2 create-snapshot \
  --volume-id "$VOLUME_ID" \
  --description "$DESCRIPTION" \
  --tag-specifications "ResourceType=snapshot,Tags=[{Key=Name,Value=${DESCRIPTION}},{Key=Source,Value=clickhouse-data}]" \
  --query "SnapshotId" \
  --output text)

echo
echo "Snapshot ID: ${SNAPSHOT_ID}"
echo "Status:      pending"
echo
echo "Monitor progress with:"
echo "  aws ec2 describe-snapshots --snapshot-ids ${SNAPSHOT_ID} --query 'Snapshots[0].{Progress:Progress,State:State}'"
echo
echo "To restore, create a new volume from the snapshot:"
echo "  aws ec2 create-volume --snapshot-id ${SNAPSHOT_ID} --availability-zone <az> --volume-type gp3"
