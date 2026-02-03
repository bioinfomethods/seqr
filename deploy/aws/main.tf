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

# Security group for VPC endpoints
resource "aws_security_group" "vpc_endpoints" {
  name        = "${local.name_prefix}-vpc-endpoints-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = local.vpc_id

  # Allow HTTPS from Clickhouse security group
  ingress {
    description     = "HTTPS from Clickhouse"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.clickhouse.id]
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
    Name = "${local.name_prefix}-vpc-endpoints-sg"
  }
}

# VPC Endpoint for ECR API
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.seqr_az1.id, aws_subnet.seqr_az2.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${local.name_prefix}-ecr-api-endpoint"
  }
}

# VPC Endpoint for ECR Docker
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.seqr_az1.id, aws_subnet.seqr_az2.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${local.name_prefix}-ecr-dkr-endpoint"
  }
}

# VPC Endpoint for S3 (Gateway type - no security group needed)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = local.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [data.aws_vpc.default.main_route_table_id]

  tags = {
    Name = "${local.name_prefix}-s3-endpoint"
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

  user_data = <<-EOF
              #!/bin/bash
              # Install PostgreSQL client
              dnf install -y postgresql15
              EOF

  user_data_replace_on_change = true

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

# Aurora PostgreSQL Module
module "aurora" {
  source = "./modules/aurora"

  name_prefix                   = local.name_prefix
  vpc_id                        = local.vpc_id
  subnet_ids                    = [aws_subnet.seqr_az1.id, aws_subnet.seqr_az2.id]
  bastion_security_group_id     = aws_security_group.bastion.id
  clickhouse_security_group_id  = aws_security_group.clickhouse.id
  instance_class                = var.aurora_instance_class
  master_username               = var.aurora_master_username
  master_password               = var.aurora_master_password
  database_name                 = var.aurora_database_name
  engine_version                = "17.6"
  backup_retention_period       = var.aurora_backup_retention_period
  skip_final_snapshot           = var.aurora_skip_final_snapshot
}

# ECR Repository for seqr-web (Django)
resource "aws_ecr_repository" "seqr_web" {
  name                 = "${local.name_prefix}-seqr-web"
  image_tag_mutability = "MUTABLE"

  tags = {
    Name = "${local.name_prefix}-seqr-web"
  }
}

# ECR Repository for Clickhouse
resource "aws_ecr_repository" "clickhouse" {
  name                 = "${local.name_prefix}-clickhouse"
  image_tag_mutability = "MUTABLE"

  tags = {
    Name = "${local.name_prefix}-clickhouse"
  }
}

# IAM role for Clickhouse instance
resource "aws_iam_role" "clickhouse" {
  name = "${local.name_prefix}-clickhouse-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${local.name_prefix}-clickhouse-role"
  }
}

# IAM policy for ECR access
resource "aws_iam_role_policy" "clickhouse_ecr" {
  name = "${local.name_prefix}-clickhouse-ecr-policy"
  role = aws_iam_role.clickhouse.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM instance profile
resource "aws_iam_instance_profile" "clickhouse" {
  name = "${local.name_prefix}-clickhouse-profile"
  role = aws_iam_role.clickhouse.name

  tags = {
    Name = "${local.name_prefix}-clickhouse-profile"
  }
}

# Security group for Clickhouse
resource "aws_security_group" "clickhouse" {
  name        = "${local.name_prefix}-clickhouse-sg"
  description = "Security group for Clickhouse database"
  vpc_id      = local.vpc_id

  # Allow Clickhouse HTTP interface from bastion
  ingress {
    description     = "Clickhouse HTTP from bastion"
    from_port       = 8123
    to_port         = 8123
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  # Allow Clickhouse native protocol from bastion
  ingress {
    description     = "Clickhouse native from bastion"
    from_port       = 9000
    to_port         = 9000
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  # Allow SSH from bastion
  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  # Allow all outbound traffic (includes PostgreSQL to Aurora and VPC endpoints)
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-clickhouse-sg"
  }
}

# Clickhouse EC2 instance
resource "aws_instance" "clickhouse" {
  ami                    = var.clickhouse_ami_id != "" ? var.clickhouse_ami_id : data.aws_ami.amazon_linux_2023.id
  instance_type          = var.clickhouse_instance_type
  key_name               = var.clickhouse_key_name
  subnet_id              = aws_subnet.seqr_az1.id
  vpc_security_group_ids = [aws_security_group.clickhouse.id]
  iam_instance_profile   = aws_iam_instance_profile.clickhouse.name

  root_block_device {
    volume_size = var.clickhouse_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = templatefile("${path.module}/user-data/clickhouse.sh", {
    ecr_repository_url = aws_ecr_repository.clickhouse.repository_url
    aws_region         = var.aws_region
  })

  user_data_replace_on_change = true

  tags = {
    Name = "${local.name_prefix}-clickhouse"
  }
}
