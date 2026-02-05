# Seqr AWS Infrastructure

This directory contains OpenTofu/Terraform configuration for deploying the Seqr application on AWS.

## Prerequisites

- OpenTofu >= 1.0 (or Terraform >= 1.0)
- AWS CLI configured with appropriate credentials
- SSH key pair created in AWS for bastion and Clickhouse instances
- S3 bucket for OpenTofu state (named: `<prefix>-seqr-<environment>-terraform-state`)
- DynamoDB table for state locking (named: `terraform-state-lock`)

## Quick Start

### 1. Set Up Backend Infrastructure

Run the setup script to create the S3 bucket and DynamoDB table:

```bash
cd scripts
chmod +x setup-backend.sh
./setup-backend.sh mcri dev ap-southeast-2
```

### 2. Configure Environment

Copy the example tfvars file and customize it:

```bash
cp terraform-dev.tfvars.example terraform-dev.tfvars
```

Edit `terraform-dev.tfvars` and update the `cost_centre` value.

### 3. Initialize OpenTofu

```bash
tofu init \
  -backend-config="bucket=mcri-seqr-dev-terraform-state" \
  -backend-config="region=ap-southeast-2"
```

### 4. Create Symlink to Environment Config

```bash
ln -sf terraform-dev.tfvars terraform.tfvars
```

### 5. Plan and Apply

```bash
tofu plan
tofu apply
```

## Architecture

See `INFRA_ARCHITECTURE.md` for detailed architecture documentation.

## Implementation Plan

See `PLAN.md` for the phased implementation plan and progress tracking.

## Resource Naming Convention

All resources follow the naming pattern:
```
<prefix>-seqr-<environment>-<component>
```

For example: `mcri-seqr-dev-bastion`

## Outputs

After applying, OpenTofu will output important information including:
- VPC ID and subnet IDs
- Name prefix used for resources
- Default tags applied to all resources

As more components are added, additional outputs will include:
- Bastion host public IP
- Aurora database endpoints
- ALB DNS name
- SSH tunnel command

## Building Custom AMIs with Packer

The Clickhouse instance uses a custom AMI built with Packer. This AMI has Docker, Clickhouse, and all configuration pre-installed for fast boot times.

### Build Clickhouse AMI

```bash
# Using the helper script (recommended)
cd scripts
./build-clickhouse-ami.sh

# Or manually with packer
cd packer/clickhouse
packer build clickhouse.pkr.hcl

# With custom variables
packer build \
  -var "aws_region=ap-southeast-2" \
  -var "prefix=mcri" \
  -var "environment=dev" \
  -var "clickhouse_version=25.12" \
  clickhouse.pkr.hcl
```

### Configuration Files

Before building the AMI, replace the placeholder config files in `packer/clickhouse/configs/` with your actual Clickhouse configuration:

- `config.xml` - Main Clickhouse server configuration
- `users.xml` - User definitions and permissions
- `named_collections.xml` - Named collections for external data sources
- `init-permissions.sql` - Initialization SQL script

See `packer/clickhouse/configs/README.md` for details.

### Deploying with Custom AMI

After building the AMI, Terraform will automatically use the latest custom AMI:

```bash
tofu apply
```

The AMI selection priority is:
1. Explicit AMI ID (if `clickhouse_ami_id` variable is set)
2. Latest custom Packer-built AMI (auto-detected)
3. Base Amazon Linux 2023 AMI (fallback)

## Accessing the Application

Once the bastion host and ALB are deployed:

1. Create SSH tunnel through bastion:
```bash
ssh -L 8080:<alb-dns-name>:80 -i ~/.ssh/<key>.pem ec2-user@<bastion-ip>
```

2. Access application at: http://localhost:8080

## Environments

Supported environments:
- `dev` - Development
- `test` - Testing
- `prod` - Production

Each environment has its own tfvars file and state.
