#!/bin/bash
# Script to authenticate Docker with AWS ECR
# Usage: ./ecr-login.sh [region]
#
# This script automatically detects the environment from terraform.tfvars

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

# Extract configuration from terraform.tfvars
REGION=$(grep '^aws_region' terraform.tfvars | sed 's/^[^=]*=[[:space:]]*"\([^"]*\)".*/\1/')
PREFIX=$(grep '^prefix' terraform.tfvars | sed 's/^[^=]*=[[:space:]]*"\([^"]*\)".*/\1/')
ENVIRONMENT=$(grep '^environment' terraform.tfvars | sed 's/^[^=]*=[[:space:]]*"\([^"]*\)".*/\1/')

# Allow region override from command line
REGION=${1:-$REGION}

# Validate we got the required values
if [ -z "$REGION" ] || [ -z "$PREFIX" ] || [ -z "$ENVIRONMENT" ]; then
  echo "Error: Could not extract required values from terraform.tfvars"
  echo "  Region: ${REGION:-<not found>}"
  echo "  Prefix: ${PREFIX:-<not found>}"
  echo "  Environment: ${ENVIRONMENT:-<not found>}"
  exit 1
fi

REPO_NAME="${PREFIX}-seqr-${ENVIRONMENT}-seqr-web"

echo "Authenticating Docker with AWS ECR..."
echo "  Region: ${REGION}"
echo "  Repository: ${REPO_NAME}"
echo ""

# Get ECR login password and authenticate Docker
aws ecr get-login-password --region ${REGION} | \
  docker login --username AWS --password-stdin \
  $(aws sts get-caller-identity --query Account --output text).dkr.ecr.${REGION}.amazonaws.com

echo ""
echo "✓ Successfully authenticated with ECR!"
echo ""
echo "Example commands to push seqr-web image:"
echo ""
echo "  # Tag your image"
echo "  docker tag seqr-web:latest \$(aws sts get-caller-identity --query Account --output text).dkr.ecr.${REGION}.amazonaws.com/${REPO_NAME}:latest"
echo ""
echo "  # Push to ECR"
echo "  docker push \$(aws sts get-caller-identity --query Account --output text).dkr.ecr.${REGION}.amazonaws.com/${REPO_NAME}:latest"
