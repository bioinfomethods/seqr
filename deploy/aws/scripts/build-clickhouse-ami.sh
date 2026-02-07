#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKER_DIR="$SCRIPT_DIR/../packer/clickhouse"

# Default values
AWS_REGION="${AWS_REGION:-ap-southeast-2}"
PREFIX="${PREFIX:-mcri}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
CLICKHOUSE_VERSION="${CLICKHOUSE_VERSION:-25.12}"

# Auto-detect subnet ID if not provided
if [ -z "$SUBNET_ID" ]; then
  echo "Auto-detecting subnet ID..."
  SUBNET_ID=$(aws ec2 describe-subnets \
    --region "$AWS_REGION" \
    --filters "Name=tag:Name,Values=${PREFIX}-seqr-${ENVIRONMENT}-az1" \
    --query "Subnets[0].SubnetId" \
    --output text 2>/dev/null)

  if [ -z "$SUBNET_ID" ] || [ "$SUBNET_ID" = "None" ]; then
    echo "ERROR: Could not auto-detect subnet ID."
    echo "Either set SUBNET_ID environment variable or ensure the subnet"
    echo "  '${PREFIX}-seqr-${ENVIRONMENT}-az1' exists in region $AWS_REGION"
    exit 1
  fi
  echo "  Found subnet: $SUBNET_ID"
fi

echo "=========================================="
echo "Building Clickhouse AMI"
echo "=========================================="
echo "  Region: $AWS_REGION"
echo "  Prefix: $PREFIX"
echo "  Environment: $ENVIRONMENT"
echo "  Clickhouse Version: $CLICKHOUSE_VERSION"
echo "  Subnet: $SUBNET_ID"
echo ""

# Check if packer is installed
if ! command -v packer &> /dev/null; then
    echo "ERROR: packer is not installed"
    echo "Install with: brew install packer (macOS) or download from https://www.packer.io/downloads"
    exit 1
fi

# Check if config files exist
if [ ! -f "$PACKER_DIR/configs/config.xml" ]; then
    echo "WARNING: Config files not found in $PACKER_DIR/configs/"
    echo "Using placeholder configs. Replace with actual configs before production use."
    echo ""
fi

cd "$PACKER_DIR"

echo "Initializing Packer plugins..."
packer init clickhouse.pkr.hcl
echo ""

echo "Running packer build..."
echo ""

packer build \
  -var "aws_region=$AWS_REGION" \
  -var "prefix=$PREFIX" \
  -var "environment=$ENVIRONMENT" \
  -var "clickhouse_version=$CLICKHOUSE_VERSION" \
  -var "subnet_id=$SUBNET_ID" \
  clickhouse.pkr.hcl

echo ""
echo "=========================================="
echo "✓ AMI built successfully!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. The new AMI will be automatically used on next 'tofu apply'"
echo "  2. Run: cd $SCRIPT_DIR/.."
echo "  3. Run: tofu apply"
echo ""
