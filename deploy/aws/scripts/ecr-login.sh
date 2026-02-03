#!/bin/bash
# Script to authenticate Docker with AWS ECR
# Usage: ./ecr-login.sh [region]

set -e

REGION=${1:-ap-southeast-2}

echo "Authenticating Docker with AWS ECR in region ${REGION}..."

# Get ECR login password and authenticate Docker
aws ecr get-login-password --region ${REGION} | \
  docker login --username AWS --password-stdin \
  $(aws sts get-caller-identity --query Account --output text).dkr.ecr.${REGION}.amazonaws.com

echo ""
echo "✓ Successfully authenticated with ECR!"
echo ""
echo "You can now push images to ECR repositories in ${REGION}"
echo ""
echo "Example commands:"
echo "  # Tag your image"
echo "  docker tag myimage:latest \$(aws sts get-caller-identity --query Account --output text).dkr.ecr.${REGION}.amazonaws.com/mcri-seqr-dev-seqr-web:latest"
echo ""
echo "  # Push to ECR"
echo "  docker push \$(aws sts get-caller-identity --query Account --output text).dkr.ecr.${REGION}.amazonaws.com/mcri-seqr-dev-seqr-web:latest"
