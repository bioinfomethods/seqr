#!/bin/bash
set -euo pipefail

# Restore a ClickHouse data volume from an EBS snapshot.
# This will:
#   1. Stop ClickHouse on the EC2 instance
#   2. Detach the current data volume
#   3. Create a new volume from the snapshot
#   4. Attach the new volume
#   5. Restart ClickHouse
#
# Run from the deploy/aws directory (where Terraform state lives).
#
# Usage:
#   ./scripts/clickhouse_snapshot_restore.sh <snapshot-id>
#
# To list available snapshots:
#   aws ec2 describe-snapshots --owner-ids self \
#     --filters "Name=tag:Project,Values=seqr" \
#     --query 'Snapshots[*].[SnapshotId,StartTime,Description,VolumeSize]' \
#     --output table

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SNAPSHOT_ID="${1:-}"
if [ -z "$SNAPSHOT_ID" ]; then
    echo "Usage: $0 <snapshot-id>"
    echo
    echo "Available snapshots:"
    aws ec2 describe-snapshots --owner-ids self \
        --filters "Name=tag:Project,Values=seqr" \
        --query 'Snapshots[*].[SnapshotId,StartTime,Description,VolumeSize]' \
        --output table
    exit 1
fi

echo "=== ClickHouse EBS Snapshot Restore ==="
echo
echo "  Snapshot ID: $SNAPSHOT_ID"
echo

# Validate snapshot exists and is completed
SNAPSHOT_STATE=$(aws ec2 describe-snapshots \
    --snapshot-ids "$SNAPSHOT_ID" \
    --query 'Snapshots[0].State' \
    --output text 2>/dev/null || true)

if [ "$SNAPSHOT_STATE" != "completed" ]; then
    echo "ERROR: Snapshot $SNAPSHOT_ID not found or not in 'completed' state (state: ${SNAPSHOT_STATE:-not found})"
    exit 1
fi

SNAPSHOT_SIZE=$(aws ec2 describe-snapshots \
    --snapshot-ids "$SNAPSHOT_ID" \
    --query 'Snapshots[0].VolumeSize' \
    --output text)

echo "  Snapshot state: $SNAPSHOT_STATE"
echo "  Snapshot size:  ${SNAPSHOT_SIZE} GB"
echo

# Get instance and volume details from Terraform
echo "Looking up ClickHouse instance from Terraform state..."
cd "$TF_DIR"

INSTANCE_ID=$(terraform output -raw clickhouse_instance_id 2>/dev/null || true)
OLD_VOLUME_ID=$(terraform output -raw clickhouse_data_volume_id 2>/dev/null || true)
NAME_PREFIX=$(terraform output -raw name_prefix 2>/dev/null || true)

if [ -z "$INSTANCE_ID" ] || [ -z "$OLD_VOLUME_ID" ]; then
    echo "ERROR: Could not find clickhouse_instance_id or clickhouse_data_volume_id in Terraform outputs."
    exit 1
fi

# Get the AZ of the instance
AZ=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].Placement.AvailabilityZone' \
    --output text)

# Get the device name of the current volume attachment
DEVICE_NAME=$(aws ec2 describe-volumes \
    --volume-ids "$OLD_VOLUME_ID" \
    --query 'Volumes[0].Attachments[0].Device' \
    --output text)

echo "  Instance ID:   $INSTANCE_ID"
echo "  Old Volume ID: $OLD_VOLUME_ID"
echo "  AZ:            $AZ"
echo "  Device:        $DEVICE_NAME"
echo

# Get bastion and ClickHouse IPs for SSH
BASTION_IP=$(terraform output -raw bastion_public_ip 2>/dev/null || true)
CH_PRIVATE_IP=$(terraform output -raw clickhouse_private_ip 2>/dev/null || true)

if [ -z "$BASTION_IP" ] || [ -z "$CH_PRIVATE_IP" ]; then
    echo "ERROR: Could not find bastion_public_ip or clickhouse_private_ip in Terraform outputs."
    exit 1
fi

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
SSH_CMD="ssh $SSH_OPTS -J ec2-user@${BASTION_IP} ec2-user@${CH_PRIVATE_IP}"

echo "=== WARNING ==="
echo "This will:"
echo "  1. Stop ClickHouse on ${CH_PRIVATE_IP}"
echo "  2. Detach volume ${OLD_VOLUME_ID}"
echo "  3. Create a new volume from snapshot ${SNAPSHOT_ID}"
echo "  4. Attach the new volume and restart ClickHouse"
echo "  5. The old volume will NOT be deleted (manual cleanup required)"
echo
read -p "Continue? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

echo
echo "--- Step 1: Stopping ClickHouse ---"
$SSH_CMD "cd /home/ec2-user/clickhouse && sudo docker compose down" || true
echo "  ✓ ClickHouse stopped"

echo
echo "--- Step 2: Unmounting data volume ---"
$SSH_CMD "sudo umount /var/lib/clickhouse" || true
echo "  ✓ Volume unmounted"

echo
echo "--- Step 3: Detaching old volume ---"
aws ec2 detach-volume --volume-id "$OLD_VOLUME_ID" --force
echo "  Waiting for volume to detach..."
aws ec2 wait volume-available --volume-ids "$OLD_VOLUME_ID"
echo "  ✓ Old volume detached"

echo
echo "--- Step 4: Creating new volume from snapshot ---"
NEW_VOLUME_ID=$(aws ec2 create-volume \
    --snapshot-id "$SNAPSHOT_ID" \
    --availability-zone "$AZ" \
    --volume-type gp3 \
    --encrypted \
    --tag-specifications "ResourceType=volume,Tags=[
        {Key=Name,Value=${NAME_PREFIX:-seqr}-clickhouse-data},
        {Key=Project,Value=seqr},
        {Key=ManagedBy,Value=script},
        {Key=RestoredFromSnapshot,Value=$SNAPSHOT_ID}
    ]" \
    --query 'VolumeId' \
    --output text)

echo "  New Volume ID: $NEW_VOLUME_ID"
echo "  Waiting for volume to be available..."
aws ec2 wait volume-available --volume-ids "$NEW_VOLUME_ID"
echo "  ✓ New volume ready"

echo
echo "--- Step 5: Attaching new volume ---"
aws ec2 attach-volume \
    --volume-id "$NEW_VOLUME_ID" \
    --instance-id "$INSTANCE_ID" \
    --device "$DEVICE_NAME"

echo "  Waiting for volume to attach..."
aws ec2 wait volume-in-use --volume-ids "$NEW_VOLUME_ID"
echo "  ✓ New volume attached"

echo
echo "--- Step 6: Mounting and starting ClickHouse ---"
$SSH_CMD "sudo /home/ec2-user/clickhouse/scripts/start-clickhouse.sh"
echo "  ✓ ClickHouse restarted"

echo
echo "=== Restore Complete ==="
echo "  New Volume ID: $NEW_VOLUME_ID"
echo "  Old Volume ID: $OLD_VOLUME_ID (still exists — delete manually when confirmed working)"
echo
echo "IMPORTANT: Terraform state still references the old volume ($OLD_VOLUME_ID)."
echo "To update Terraform state, run:"
echo "  cd $TF_DIR"
echo "  terraform state rm aws_ebs_volume.clickhouse_data"
echo "  terraform state rm aws_volume_attachment.clickhouse_data"
echo "  terraform import aws_ebs_volume.clickhouse_data $NEW_VOLUME_ID"
echo "  terraform import aws_volume_attachment.clickhouse_data $DEVICE_NAME:$NEW_VOLUME_ID:$INSTANCE_ID"
echo
echo "Then delete the old volume:"
echo "  aws ec2 delete-volume --volume-id $OLD_VOLUME_ID"
