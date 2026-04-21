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

# Data sources
data "aws_caller_identity" "current" {}

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

# Route table associations for seqr subnets (ensures S3 gateway endpoint routes are available)
resource "aws_route_table_association" "seqr_az1" {
  subnet_id      = aws_subnet.seqr_az1.id
  route_table_id = data.aws_vpc.default.main_route_table_id
}

resource "aws_route_table_association" "seqr_az2" {
  subnet_id      = aws_subnet.seqr_az2.id
  route_table_id = data.aws_vpc.default.main_route_table_id
}

# Security group for VPC endpoints
resource "aws_security_group" "vpc_endpoints" {
  name        = "${local.name_prefix}-vpc-endpoints-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = local.vpc_id

  # Allow HTTPS from within the VPC (ECS Fargate, Clickhouse, etc.)
  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
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
  security_group_ids  = [aws_security_group.vpc_endpoints.id, aws_security_group.ecs_service.id]
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

# VPC Endpoint for CloudWatch Logs (required for Fargate logging)
resource "aws_vpc_endpoint" "logs" {
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.seqr_az1.id, aws_subnet.seqr_az2.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${local.name_prefix}-logs-endpoint"
  }
}

# VPC Endpoint for SSM Messages (required for ECS Exec in private subnets)
resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.seqr_az1.id, aws_subnet.seqr_az2.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${local.name_prefix}-ssmmessages-endpoint"
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

# =============================================================================
# Secrets Manager for sensitive OIDC configuration
# =============================================================================

resource "aws_secretsmanager_secret" "oidc_client_secret" {
  count = var.social_auth_client_secret != "" ? 1 : 0

  name        = "${local.name_prefix}/oidc/client-secret"
  description = "OIDC client secret for Keycloak authentication"

  tags = {
    Name = "${local.name_prefix}-oidc-client-secret"
  }
}

resource "aws_secretsmanager_secret_version" "oidc_client_secret" {
  count = var.social_auth_client_secret != "" ? 1 : 0

  secret_id     = aws_secretsmanager_secret.oidc_client_secret[0].id
  secret_string = var.social_auth_client_secret
}

# Route53 private hosted zone for Keycloak hostname resolution within the VPC.
# Maps the Keycloak hostname to the bastion's private IP so that ECS Fargate
# containers (and anything else in the VPC) resolve it to the SSH tunnel endpoint.
# Note: This overrides public DNS for this hostname within the entire VPC.
resource "aws_route53_zone" "keycloak" {
  count = var.keycloak_host != "" ? 1 : 0

  name = var.keycloak_host

  vpc {
    vpc_id = local.vpc_id
  }

  tags = {
    Name = "${local.name_prefix}-keycloak-dns"
  }
}

resource "aws_route53_record" "keycloak" {
  count = var.keycloak_host != "" ? 1 : 0

  zone_id = aws_route53_zone.keycloak[0].zone_id
  name    = var.keycloak_host
  type    = "A"
  ttl     = 60
  records = [aws_instance.bastion.private_ip]
}

# Separate security group rule to avoid cycle:
# bastion SG -> ecs_service SG -> alb SG -> bastion EIP -> bastion instance -> bastion SG
resource "aws_security_group_rule" "bastion_keycloak_from_ecs" {
  type                     = "ingress"
  description              = "Keycloak tunnel from ECS Fargate"
  from_port                = 8888
  to_port                  = 8888
  protocol                 = "tcp"
  security_group_id        = aws_security_group.bastion.id
  source_security_group_id = aws_security_group.ecs_service.id
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

# Get latest custom Clickhouse AMI (built with Packer)
data "aws_ami" "clickhouse_custom" {
  most_recent = true
  owners      = ["self"]  # Your AWS account

  filter {
    name   = "name"
    values = ["${var.prefix}-seqr-${var.environment}-clickhouse-*"]
  }

  filter {
    name   = "tag:Environment"
    values = [var.environment]
  }
}

# IAM role for bastion host (S3 access for uploading data files)
resource "aws_iam_role" "bastion" {
  name = "${local.name_prefix}-bastion-role"

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
    Name = "${local.name_prefix}-bastion-role"
  }
}

resource "aws_iam_role_policy" "bastion_s3" {
  name = "${local.name_prefix}-bastion-s3-policy"
  role = aws_iam_role.bastion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.seqr_data.arn,
          "${aws_s3_bucket.seqr_data.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${local.name_prefix}-bastion-profile"
  role = aws_iam_role.bastion.name

  tags = {
    Name = "${local.name_prefix}-bastion-profile"
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
  iam_instance_profile        = aws_iam_instance_profile.bastion.name

  root_block_device {
    volume_size = 32
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = <<-EOF
              #!/bin/bash
              # Install PostgreSQL client
              dnf install -y postgresql15

              # Enable GatewayPorts for SSH reverse tunnels (Keycloak OIDC)
              # Allows remote SSH tunnels to listen on all interfaces, not just localhost
              if ! grep -q '^GatewayPorts' /etc/ssh/sshd_config; then
                echo 'GatewayPorts clientspecified' >> /etc/ssh/sshd_config
                systemctl restart sshd
              fi
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
  ecs_security_group_id         = aws_security_group.ecs_service.id
  instance_class                = var.aurora_instance_class
  master_username               = var.aurora_master_username
  master_password               = var.aurora_master_password
  database_name                 = var.aurora_database_name
  engine_version                = "17.6"
  backup_retention_period       = var.aurora_backup_retention_period
  skip_final_snapshot           = var.aurora_skip_final_snapshot
}

# S3 bucket for seqr application data (ClinVar files, variant datasets, etc.)
resource "aws_s3_bucket" "seqr_data" {
  bucket = "${local.name_prefix}-seqr-data"

  tags = {
    Name = "${local.name_prefix}-seqr-data"
  }
}

resource "aws_s3_bucket_versioning" "seqr_data" {
  bucket = aws_s3_bucket.seqr_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "seqr_data" {
  bucket = aws_s3_bucket.seqr_data.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "seqr_data" {
  bucket = aws_s3_bucket.seqr_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ECR pull-through cache for public ECR images (e.g., Redis)
resource "aws_ecr_pull_through_cache_rule" "ecr_public" {
  ecr_repository_prefix = "ecr-public"
  upstream_registry_url = "public.ecr.aws"
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

# IAM policy for S3 read access (Parquet import, reference data, etc.)
resource "aws_iam_role_policy" "clickhouse_s3_read" {
  name = "${local.name_prefix}-clickhouse-s3-read-policy"
  role = aws_iam_role.clickhouse.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.seqr_data.arn,
          "${aws_s3_bucket.seqr_data.arn}/*"
        ]
      }
    ]
  })
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

  # Allow Clickhouse HTTP from ECS Fargate service
  ingress {
    description     = "Clickhouse HTTP from ECS Fargate service"
    from_port       = 8123
    to_port         = 8123
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_service.id]
  }

  # Allow Clickhouse native protocol from ECS Fargate service
  ingress {
    description     = "Clickhouse native from ECS Fargate service"
    from_port       = 9000
    to_port         = 9000
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_service.id]
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
  # Use custom AMI if available, otherwise fall back to base Amazon Linux
  # Priority: 1) Explicit AMI ID, 2) Custom Packer AMI, 3) Base Amazon Linux
  ami = var.clickhouse_ami_id != "" ? var.clickhouse_ami_id : (
    try(data.aws_ami.clickhouse_custom.id, data.aws_ami.amazon_linux_2023.id)
  )
  instance_type          = var.clickhouse_instance_type
  key_name               = var.clickhouse_key_name
  subnet_id              = aws_subnet.seqr_az1.id
  vpc_security_group_ids = [aws_security_group.clickhouse.id]
  iam_instance_profile   = aws_iam_instance_profile.clickhouse.name

  root_block_device {
    volume_size = var.clickhouse_root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  # Pass Aurora connection details, ECR info, and data volume device to ClickHouse instance.
  # The start-clickhouse.sh script reads these from /etc/environment to:
  #   1. Mount the dedicated data volume at /var/lib/clickhouse
  #   2. Configure named_collections.xml with PostgreSQL connection details
  #   3. Start ClickHouse via docker compose
  user_data = <<-EOF
#!/bin/bash
cat >> /etc/environment <<'ENVEOF'
POSTGRES_HOST=${module.aurora.cluster_endpoint}
POSTGRES_PORT=${module.aurora.cluster_port}
POSTGRES_USER=${var.aurora_master_username}
POSTGRES_PASSWORD=${var.aurora_master_password}
POSTGRES_DATABASE=${var.aurora_database_name}
ECR_REPOSITORY_URL=${aws_ecr_repository.clickhouse.repository_url}
AWS_REGION=${var.aws_region}
CLICKHOUSE_DATA_DEVICE=/dev/nvme1n1
ENVEOF

# Configure and start ClickHouse (mounts data volume, substitutes named_collections.xml, starts containers)
/home/ec2-user/clickhouse/scripts/start-clickhouse.sh
EOF

  user_data_replace_on_change = true

  tags = {
    Name = "${local.name_prefix}-clickhouse"
  }
}

# Dedicated EBS volume for ClickHouse data (separate from root for easy snapshots)
resource "aws_ebs_volume" "clickhouse_data" {
  availability_zone = data.aws_availability_zones.available.names[0]
  size              = var.clickhouse_data_volume_size
  type              = "gp3"
  encrypted         = true

  tags = {
    Name = "${local.name_prefix}-clickhouse-data"
  }
}

resource "aws_volume_attachment" "clickhouse_data" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.clickhouse_data.id
  instance_id = aws_instance.clickhouse.id

  # Prevent Terraform from force-detaching (which would destroy data)
  force_detach = false
}
