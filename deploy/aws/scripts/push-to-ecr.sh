#!/bin/bash
# Script to push a Docker image to AWS ECR
# Usage: ./push-to-ecr.sh <source-image:tag> [target-tag]
#
# Example: ./push-to-ecr.sh gcr.io/seqr-project/seqr:gcloud-prod gcloud-prod
#          ./push-to-ecr.sh myimage:latest latest

set -e

# Check arguments
if [ $# -lt 1 ]; then
  echo "Usage: $0 <source-image:tag> [target-tag]"
  echo ""
  echo "Examples:"
  echo "  $0 gcr.io/seqr-project/seqr:gcloud-prod gcloud-prod"
  echo "  $0 myimage:latest latest"
  echo "  $0 gcr.io/seqr-project/seqr:gcloud-prod  # Uses 'latest' as target tag"
  exit 1
fi

SOURCE_IMAGE=$1
TARGET_TAG=${2:-latest}

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

REPO_NAME="${PREFIX}-seqr-${ENVIRONMENT}-seqr-web"
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
ECR_REPO="${AWS_ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/${REPO_NAME}"

echo "Pushing image to ECR..."
echo "  Source: ${SOURCE_IMAGE}"
echo "  Target: ${ECR_REPO}:${TARGET_TAG}"
echo ""

# Authenticate with ECR
echo "Authenticating with ECR..."
aws ecr get-login-password --region ${REGION} | \
  docker login --username AWS --password-stdin ${AWS_ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com

# Pull the source image
echo ""
echo "Pulling source image..."
docker pull ${SOURCE_IMAGE}

# Tag for ECR
echo ""
echo "Tagging image for ECR..."
docker tag ${SOURCE_IMAGE} ${ECR_REPO}:${TARGET_TAG}

# Push to ECR
echo ""
echo "Pushing to ECR..."
docker push ${ECR_REPO}:${TARGET_TAG}

echo ""
echo "✓ Successfully pushed image to ECR!"
echo ""
echo "Image available at: ${ECR_REPO}:${TARGET_TAG}"
