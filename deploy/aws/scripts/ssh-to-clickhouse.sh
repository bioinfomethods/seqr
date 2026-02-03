#!/bin/bash
# Script to SSH to Clickhouse instance via bastion jump host
# Automatically retrieves IP addresses from Terraform outputs

set -e

# Change to the deploy/aws directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
cd "$DEPLOY_DIR"

# Check if terraform.tfvars exists
if [ ! -f "terraform.tfvars" ]; then
  echo "Error: terraform.tfvars not found in $DEPLOY_DIR"
  echo "Please create a symlink: ln -sf terraform-<env>.tfvars terraform.tfvars"
  exit 1
fi

# Extract key name from terraform.tfvars
KEY_NAME=$(grep '^bastion_key_name' terraform.tfvars | sed 's/^[^=]*=[[:space:]]*"\([^"]*\)".*/\1/')

if [ -z "$KEY_NAME" ]; then
  echo "Error: Could not extract bastion_key_name from terraform.tfvars"
  exit 1
fi

# Get IP addresses from Terraform outputs
echo "Retrieving IP addresses from Terraform outputs..."
BASTION_IP=$(tofu output -raw bastion_public_ip)
CLICKHOUSE_IP=$(tofu output -raw clickhouse_private_ip)

if [ -z "$BASTION_IP" ] || [ -z "$CLICKHOUSE_IP" ]; then
  echo "Error: Could not retrieve IP addresses from Terraform outputs"
  echo "  Bastion IP: ${BASTION_IP:-<not found>}"
  echo "  Clickhouse IP: ${CLICKHOUSE_IP:-<not found>}"
  exit 1
fi

echo "Connecting to Clickhouse instance..."
echo "  Bastion: ${BASTION_IP}"
echo "  Clickhouse: ${CLICKHOUSE_IP}"
echo "  Key: ~/.ssh/${KEY_NAME}"
echo ""

# SSH to Clickhouse via bastion jump host
ssh -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -i ~/.ssh/${KEY_NAME} \
    -J ec2-user@${BASTION_IP} \
    ec2-user@${CLICKHOUSE_IP}

echo "Done"

