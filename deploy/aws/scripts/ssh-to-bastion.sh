#!/bin/bash
# Script to SSH to bastion host
# Automatically retrieves IP address from Terraform outputs

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

# Get IP address from Terraform outputs
echo "Retrieving IP address from Terraform outputs..."
BASTION_IP=$(tofu output -raw bastion_public_ip)

if [ -z "$BASTION_IP" ]; then
  echo "Error: Could not retrieve bastion IP address from Terraform outputs"
  exit 1
fi

# Get ALB DNS name from Terraform outputs for port forwarding
echo "Retrieving ALB DNS name from Terraform outputs..."
ALB_DNS=$(tofu output -raw alb_dns_name 2>/dev/null || true)

if [ -z "$ALB_DNS" ]; then
  echo "Warning: Could not retrieve ALB DNS name from Terraform outputs"
  echo "         ALB port forwarding will not be configured"
fi

# Get Aurora cluster endpoint from Terraform outputs for port forwarding
echo "Retrieving Aurora cluster endpoint from Terraform outputs..."
AURORA_ENDPOINT=$(tofu output -raw aurora_cluster_endpoint 2>/dev/null || true)
AURORA_PORT=$(tofu output -raw aurora_cluster_port 2>/dev/null || true)
AURORA_PORT="${AURORA_PORT:-5432}"

if [ -z "$AURORA_ENDPOINT" ]; then
  echo "Warning: Could not retrieve Aurora cluster endpoint from Terraform outputs"
  echo "         Aurora port forwarding will not be configured"
fi

# Get ClickHouse private IP from Terraform outputs for port forwarding
echo "Retrieving ClickHouse private IP from Terraform outputs..."
CLICKHOUSE_IP=$(tofu output -raw clickhouse_private_ip 2>/dev/null || true)

if [ -z "$CLICKHOUSE_IP" ]; then
  echo "Warning: Could not retrieve ClickHouse private IP from Terraform outputs"
  echo "         ClickHouse port forwarding will not be configured"
fi

LOCAL_PORT="${LOCAL_PORT:-8167}"
LOCAL_AURORA_PORT="${LOCAL_AURORA_PORT:-8168}"
LOCAL_CLICKHOUSE_PORT="${LOCAL_CLICKHOUSE_PORT:-8169}"
LOCAL_CLICKHOUSE_HTTP_PORT="${LOCAL_CLICKHOUSE_HTTP_PORT:-8170}"

# Copy custom terminfo directory if it exists
if [ -d ~/.terminfo ]; then
  echo "Copying custom terminfo directory..."
  scp -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -i ~/.ssh/${KEY_NAME} \
      -r ~/.terminfo \
      ec2-user@${BASTION_IP}:~/
  echo "✓ Terminfo directory copied"
  echo ""
fi

echo "Connecting to bastion host..."
echo "  Bastion: ${BASTION_IP}"
echo "  Key: ~/.ssh/${KEY_NAME}"
if [ -n "$ALB_DNS" ]; then
  echo "  Port forward: localhost:${LOCAL_PORT} -> ${ALB_DNS}:80 (ALB)"
fi
if [ -n "$AURORA_ENDPOINT" ]; then
  echo "  Port forward: localhost:${LOCAL_AURORA_PORT} -> ${AURORA_ENDPOINT}:${AURORA_PORT} (Aurora)"
fi
if [ -n "$CLICKHOUSE_IP" ]; then
  echo "  Port forward: localhost:${LOCAL_CLICKHOUSE_PORT} -> ${CLICKHOUSE_IP}:9000 (ClickHouse native)"
  echo "  Port forward: localhost:${LOCAL_CLICKHOUSE_HTTP_PORT} -> ${CLICKHOUSE_IP}:8123 (ClickHouse HTTP/JDBC)"
fi
echo ""

# Build SSH command with optional port forwarding
# -A enables agent forwarding so local SSH keys can be used to hop to other instances (e.g., ClickHouse)
SSH_ARGS=(
  -A
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -i ~/.ssh/${KEY_NAME}
)

if [ -n "$ALB_DNS" ]; then
  SSH_ARGS+=(-L "${LOCAL_PORT}:${ALB_DNS}:80")
fi

if [ -n "$AURORA_ENDPOINT" ]; then
  SSH_ARGS+=(-L "${LOCAL_AURORA_PORT}:${AURORA_ENDPOINT}:${AURORA_PORT}")
fi

if [ -n "$CLICKHOUSE_IP" ]; then
  SSH_ARGS+=(-L "${LOCAL_CLICKHOUSE_PORT}:${CLICKHOUSE_IP}:9000")
  SSH_ARGS+=(-L "${LOCAL_CLICKHOUSE_HTTP_PORT}:${CLICKHOUSE_IP}:8123")
fi

# SSH to bastion host
ssh "${SSH_ARGS[@]}" ec2-user@${BASTION_IP}

echo "Done"
