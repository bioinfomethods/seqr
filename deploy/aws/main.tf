# Seqr AWS Infrastructure - Main Configuration

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  backend "s3" {
    # Backend configuration will be provided via backend config file or CLI
    # Example: terraform init -backend-config="bucket=<prefix>-seqr-<env>-terraform-state"
    key            = "terraform.tfstate"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = local.default_tags
  }
}

# Local variables for tagging and naming
locals {
  # Resource name prefix following convention: <prefix>-seqr-<environment>-<component>
  name_prefix = "${var.prefix}-seqr-${var.environment}"
  
  # Default tags applied to all resources
  default_tags = {
    Environment = var.environment
    CostCentre  = var.cost_centre
    Project     = "seqr"
    ManagedBy   = "terraform"
  }
  
  # VPC ID - use provided or default VPC
  vpc_id = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default.id
}

# Data sources for VPC and subnets
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
}
