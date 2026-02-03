#!/bin/bash
# Script to create S3 bucket and DynamoDB table for Terraform backend
# Usage: ./setup-backend.sh <prefix> <environment> [region]

set -e

# Check arguments
if [ $# -lt 2 ]; then
  echo "Usage: $0 <prefix> <environment> [region]"
  echo "Example: $0 mcri dev ap-southeast-2"
  exit 1
fi

PREFIX=$1
ENVIRONMENT=$2
REGION=${3:-ap-southeast-2}

BUCKET_NAME="${PREFIX}-seqr-${ENVIRONMENT}-terraform-state"
TABLE_NAME="terraform-state-lock"

echo "Creating Terraform backend infrastructure..."
echo "  Prefix: ${PREFIX}"
echo "  Environment: ${ENVIRONMENT}"
echo "  Region: ${REGION}"
echo "  Bucket: ${BUCKET_NAME}"
echo "  DynamoDB Table: ${TABLE_NAME}"
echo ""

# Create S3 bucket for Terraform state
echo "Creating S3 bucket..."
if [ "${REGION}" = "us-east-1" ]; then
  # us-east-1 doesn't support LocationConstraint
  aws s3api create-bucket \
    --bucket ${BUCKET_NAME} \
    --region ${REGION}
else
  aws s3api create-bucket \
    --bucket ${BUCKET_NAME} \
    --region ${REGION} \
    --create-bucket-configuration LocationConstraint=${REGION}
fi

# Enable versioning on the bucket
echo "Enabling versioning..."
aws s3api put-bucket-versioning \
  --bucket ${BUCKET_NAME} \
  --versioning-configuration Status=Enabled

# Enable encryption on the bucket
echo "Enabling encryption..."
aws s3api put-bucket-encryption \
  --bucket ${BUCKET_NAME} \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      },
      "BucketKeyEnabled": true
    }]
  }'

# Block public access to the bucket
echo "Blocking public access..."
aws s3api put-public-access-block \
  --bucket ${BUCKET_NAME} \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Create DynamoDB table for state locking
echo "Creating DynamoDB table..."
aws dynamodb create-table \
  --table-name ${TABLE_NAME} \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ${REGION} \
  --tags Key=Environment,Value=${ENVIRONMENT} Key=Project,Value=seqr Key=ManagedBy,Value=script

echo ""
echo "✓ Backend infrastructure created successfully!"
echo ""
echo "Next steps:"
echo "  1. Initialize OpenTofu with:"
echo "     tofu init -backend-config=\"bucket=${BUCKET_NAME}\" -backend-config=\"region=${REGION}\""
echo ""
echo "  2. Create your terraform-${ENVIRONMENT}.tfvars file from the example"
echo "  3. Create symlink: ln -sf terraform-${ENVIRONMENT}.tfvars terraform.tfvars"
echo "  4. Run: tofu plan"
