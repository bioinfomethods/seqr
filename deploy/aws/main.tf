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

# Get availability zones for the region
data "aws_availability_zones" "available" {
  state = "available"
}

# Create dedicated subnet for seqr infrastructure
resource "aws_subnet" "seqr" {
  vpc_id            = local.vpc_id
  cidr_block        = var.subnet_cidr
  availability_zone = data.aws_availability_zones.available.names[0]
  
  tags = {
    Name = "${local.name_prefix}-subnet"
  }
}

# Security group for bastion host
resource "aws_security_group" "bastion" {
  name        = "${local.name_prefix}-bastion-sg"
  description = "Security group for bastion host"
  vpc_id      = local.vpc_id

  # Allow SSH from specified CIDR blocks
  dynamic "ingress" {
    for_each = var.allowed_ssh_cidrs
    content {
      description = "SSH from allowed CIDR"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  # Allow all outbound traffic
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-bastion-sg"
  }
}

# Get latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Bastion host EC2 instance
resource "aws_instance" "bastion" {
  ami                         = var.bastion_ami_id != "" ? var.bastion_ami_id : data.aws_ami.amazon_linux_2023.id
  instance_type               = var.bastion_instance_type
  key_name                    = var.bastion_key_name
  subnet_id                   = aws_subnet.seqr.id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  associate_public_ip_address = true

  tags = {
    Name = "${local.name_prefix}-bastion"
  }
}

# Elastic IP for bastion host
resource "aws_eip" "bastion" {
  instance = aws_instance.bastion.id
  domain   = "vpc"

  tags = {
    Name = "${local.name_prefix}-bastion-eip"
  }

  depends_on = [aws_instance.bastion]
}
