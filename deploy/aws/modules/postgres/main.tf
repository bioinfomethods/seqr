# PostgreSQL (RDS) Module

# Security group for RDS PostgreSQL
resource "aws_security_group" "postgres" {
  name        = "${var.name_prefix}-postgres-sg"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = var.vpc_id

  # Allow PostgreSQL from bastion host
  ingress {
    description     = "PostgreSQL from bastion"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.bastion_security_group_id]
  }

  # Allow PostgreSQL from Clickhouse (PostgreSQL engine / named collection)
  ingress {
    description     = "PostgreSQL from Clickhouse"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.clickhouse_security_group_id]
  }

  # Allow PostgreSQL from ECS Fargate service
  ingress {
    description     = "PostgreSQL from ECS Fargate"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.ecs_security_group_id]
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
    Name = "${var.name_prefix}-postgres-sg"
  }
}

# DB subnet group (RDS requires subnets in at least 2 AZs, even when Multi-AZ is off)
resource "aws_db_subnet_group" "postgres" {
  name       = "${var.name_prefix}-postgres-subnet-group"
  subnet_ids = var.subnet_ids

  tags = {
    Name = "${var.name_prefix}-postgres-subnet-group"
  }
}

# RDS PostgreSQL instance
resource "aws_db_instance" "seqr" {
  identifier     = "${var.name_prefix}-postgres"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  # Storage: starts at allocated_storage, autoscales up to max_allocated_storage
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.database_name
  username = var.master_username
  password = var.master_password
  port     = 5432

  multi_az               = var.multi_az
  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.postgres.id]
  publicly_accessible    = false

  backup_retention_period = var.backup_retention_period
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:30-sun:05:30"
  copy_tags_to_snapshot   = true

  auto_minor_version_upgrade = false
  deletion_protection        = var.deletion_protection

  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name_prefix}-postgres-final-snapshot"

  tags = {
    Name = "${var.name_prefix}-postgres"
  }
}
