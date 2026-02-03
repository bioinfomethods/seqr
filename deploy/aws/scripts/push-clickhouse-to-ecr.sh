#!/bin/bash
# Script to push Clickhouse Docker image to AWS ECR
# Usage: ./push-clickhouse-to-ecr.sh [clickhouse-version]
#
# Example: ./push-clickhouse-to-ecr.sh latest
#          ./push-clickhouse-to-ecr.sh 24.1

set -e

CLICKHOUSE_VERSION=${1:-latest}
SOURCE_IMAGE="clickhouse/clickhouse-server:${CLICKHOUSE_VERSION}"

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

# Extract configuration from terraform.tfvars
REGION=$(grep '^aws_region' terraform.tfvars | sed 's/^[^=]*=[[:space:]]*"\([^"]*\)".*/\1/')
PREFIX=$(grep '^prefix' terraform.tfvars | sed 's/^[^=]*=[[:space:]]*"\([^"]*\)".*/\1/')
ENVIRONMENT=$(grep '^environment' terraform.tfvars | sed 's/^[^=]*=[[:space:]]*"\([^"]*\)".*/\1/')

# Validate we got the required values
if [ -z "$REGION" ] || [ -z "$PREFIX" ] || [ -z "$ENVIRONMENT" ]; then
  echo "Error: Could not extract required values from terraform.tfvars"
  exit 1
fi

REPO_NAME="${PREFIX}-seqr-${ENVIRONMENT}-clickhouse"
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
ECR_REPO="${AWS_ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/${REPO_NAME}"

echo "Pushing Clickhouse image to ECR..."
echo "  Source: ${SOURCE_IMAGE}"
echo "  Target: ${ECR_REPO}:latest"
echo ""

# Authenticate with ECR
echo "Authenticating with ECR..."
aws ecr get-login-password --region ${REGION} | \
  docker login --username AWS --password-stdin ${AWS_ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com

# Pull the Clickhouse image from Docker Hub
echo ""
echo "Pulling Clickhouse image from Docker Hub..."
docker pull ${SOURCE_IMAGE}

# Tag for ECR
echo ""
echo "Tagging image for ECR..."
docker tag ${SOURCE_IMAGE} ${ECR_REPO}:latest

# Push to ECR
echo ""
echo "Pushing to ECR..."
docker push ${ECR_REPO}:latest

echo ""
echo "✓ Successfully pushed Clickhouse image to ECR!"
echo ""
echo "Image available at: ${ECR_REPO}:latest"
echo ""
echo "Next steps:"
echo "  1. Run: tofu apply"
echo "  2. The Clickhouse instance will pull the image from ECR on startup"
