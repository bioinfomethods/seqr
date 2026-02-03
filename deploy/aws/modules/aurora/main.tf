# Aurora PostgreSQL Module

# Security group for Aurora PostgreSQL
resource "aws_security_group" "aurora" {
  name        = "${var.name_prefix}-aurora-sg"
  description = "Security group for Aurora PostgreSQL"
  vpc_id      = var.vpc_id

  # Allow PostgreSQL from bastion host
  ingress {
    description     = "PostgreSQL from bastion"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.bastion_security_group_id]
  }

  # Allow PostgreSQL from Clickhouse (if security group provided)
  dynamic "ingress" {
    for_each = var.clickhouse_security_group_id != "" ? [1] : []
    content {
      description     = "PostgreSQL from Clickhouse"
      from_port       = 5432
      to_port         = 5432
      protocol        = "tcp"
      security_groups = [var.clickhouse_security_group_id]
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
    Name = "${var.name_prefix}-aurora-sg"
  }
}

# DB subnet group for Aurora (requires subnets in at least 2 AZs)
resource "aws_db_subnet_group" "aurora" {
  name       = "${var.name_prefix}-aurora-subnet-group"
  subnet_ids = var.subnet_ids

  tags = {
    Name = "${var.name_prefix}-aurora-subnet-group"
  }
}

# Aurora PostgreSQL cluster
resource "aws_rds_cluster" "seqr" {
  cluster_identifier      = "${var.name_prefix}-aurora-cluster"
  engine                  = "aurora-postgresql"
  engine_mode             = "provisioned"
  engine_version          = var.engine_version
  database_name           = var.database_name
  master_username         = var.master_username
  master_password         = var.master_password
  backup_retention_period = var.backup_retention_period
  preferred_backup_window = "03:00-04:00"
  db_subnet_group_name    = aws_db_subnet_group.aurora.name
  vpc_security_group_ids  = [aws_security_group.aurora.id]
  skip_final_snapshot     = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name_prefix}-aurora-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  tags = {
    Name = "${var.name_prefix}-aurora-cluster"
  }
}

# Aurora PostgreSQL instance
resource "aws_rds_cluster_instance" "seqr" {
  identifier         = "${var.name_prefix}-aurora-instance-1"
  cluster_identifier = aws_rds_cluster.seqr.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.seqr.engine
  engine_version     = aws_rds_cluster.seqr.engine_version

  tags = {
    Name = "${var.name_prefix}-aurora-instance-1"
  }
}
