#!/bin/bash
set -e

# Create a subnet in the default VPC for Packer builds
# This subnet is needed because the default VPC has no subnets configured

VPC_ID="vpc-de08fdb8"
CIDR_BLOCK="172.31.240.0/24"
AZ="ap-southeast-2a"
SUBNET_NAME="packer-build-subnet"

echo "Creating subnet for Packer builds..."
echo "  VPC ID: $VPC_ID"
echo "  CIDR Block: $CIDR_BLOCK"
echo "  Availability Zone: $AZ"
echo ""

aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block "$CIDR_BLOCK" \
  --availability-zone "$AZ" \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$SUBNET_NAME}]"

echo ""
echo "✓ Subnet created successfully!"
echo ""
echo "The subnet will be automatically used by Packer for building AMIs."
