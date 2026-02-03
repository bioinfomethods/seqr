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

# Create dedicated subnets for seqr infrastructure (2 AZs required for Aurora)
resource "aws_subnet" "seqr_az1" {
  vpc_id            = local.vpc_id
  cidr_block        = var.subnet_cidr_az1
  availability_zone = data.aws_availability_zones.available.names[0]
  
  tags = {
    Name = "${local.name_prefix}-subnet-az1"
  }
}

resource "aws_subnet" "seqr_az2" {
  vpc_id            = local.vpc_id
  cidr_block        = var.subnet_cidr_az2
  availability_zone = data.aws_availability_zones.available.names[1]
  
  tags = {
    Name = "${local.name_prefix}-subnet-az2"
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
  subnet_id                   = aws_subnet.seqr_az1.id
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

# Security group for Aurora PostgreSQL
resource "aws_security_group" "aurora" {
  name        = "${local.name_prefix}-aurora-sg"
  description = "Security group for Aurora PostgreSQL"
  vpc_id      = local.vpc_id

  # Allow PostgreSQL from bastion host
  ingress {
    description     = "PostgreSQL from bastion"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
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
    Name = "${local.name_prefix}-aurora-sg"
  }
}

# DB subnet group for Aurora (requires subnets in at least 2 AZs)
resource "aws_db_subnet_group" "aurora" {
  name       = "${local.name_prefix}-aurora-subnet-group"
  subnet_ids = [aws_subnet.seqr_az1.id, aws_subnet.seqr_az2.id]

  tags = {
    Name = "${local.name_prefix}-aurora-subnet-group"
  }
}

# Aurora PostgreSQL cluster
resource "aws_rds_cluster" "seqr" {
  cluster_identifier      = "${local.name_prefix}-aurora-cluster"
  engine                  = "aurora-postgresql"
  engine_mode             = "provisioned"
  engine_version          = "17.2"
  database_name           = var.aurora_database_name
  master_username         = var.aurora_master_username
  master_password         = var.aurora_master_password
  backup_retention_period = var.aurora_backup_retention_period
  preferred_backup_window = "03:00-04:00"
  db_subnet_group_name    = aws_db_subnet_group.aurora.name
  vpc_security_group_ids  = [aws_security_group.aurora.id]
  skip_final_snapshot     = var.aurora_skip_final_snapshot
  final_snapshot_identifier = var.aurora_skip_final_snapshot ? null : "${local.name_prefix}-aurora-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  tags = {
    Name = "${local.name_prefix}-aurora-cluster"
  }
}

# Aurora PostgreSQL instance
resource "aws_rds_cluster_instance" "seqr" {
  identifier         = "${local.name_prefix}-aurora-instance-1"
  cluster_identifier = aws_rds_cluster.seqr.id
  instance_class     = var.aurora_instance_class
  engine             = aws_rds_cluster.seqr.engine
  engine_version     = aws_rds_cluster.seqr.engine_version

  tags = {
    Name = "${local.name_prefix}-aurora-instance-1"
  }
}
