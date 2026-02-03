#!/bin/bash
set -e

# Log all output
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "Starting Clickhouse setup at $(date)"

# Install Docker and AWS CLI
echo "Installing Docker and AWS CLI..."
dnf install -y docker aws-cli

# Start Docker
echo "Starting Docker service..."
systemctl enable docker
systemctl start docker

# Wait for Docker to be ready
sleep 5

# Authenticate with ECR
echo "Authenticating with ECR..."
aws ecr get-login-password --region ${aws_region} | \
  docker login --username AWS --password-stdin ${ecr_repository_url}

# Pull Clickhouse image from ECR
echo "Pulling Clickhouse image from ECR..."
docker pull ${ecr_repository_url}:latest

# Create directory for Clickhouse data
echo "Creating Clickhouse data directory..."
mkdir -p /var/lib/clickhouse

# Run Clickhouse container
echo "Starting Clickhouse container..."
docker run -d \
  --name clickhouse-server \
  --restart unless-stopped \
  -p 8123:8123 \
  -p 9000:9000 \
  -v /var/lib/clickhouse:/var/lib/clickhouse \
  ${ecr_repository_url}:latest

# Wait for Clickhouse to be ready
echo "Waiting for Clickhouse to start..."
sleep 10

# Check if container is running
if docker ps | grep -q clickhouse-server; then
  echo "✓ Clickhouse container started successfully"
else
  echo "✗ Clickhouse container failed to start"
  docker logs clickhouse-server
  exit 1
fi

echo "Clickhouse setup completed at $(date)"
