# Seqr AWS Infrastructure - ECS Fargate for seqr-web (Django)

# ECS Cluster
resource "aws_ecs_cluster" "seqr" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "${local.name_prefix}-cluster"
  }
}

# =============================================================================
# Step 2: IAM Roles
# =============================================================================

# ECS Task Execution Role - used by ECS agent to pull images and write logs
resource "aws_iam_role" "ecs_task_execution" {
  name = "${local.name_prefix}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${local.name_prefix}-ecs-task-execution-role"
  }
}

# Attach the AWS managed policy for ECS task execution
resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Task Role - permissions for the running container itself
resource "aws_iam_role" "ecs_task" {
  name = "${local.name_prefix}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${local.name_prefix}-ecs-task-role"
  }
}

# =============================================================================
# Step 3: CloudWatch Log Group
# =============================================================================

resource "aws_cloudwatch_log_group" "seqr_web" {
  name              = "/ecs/${local.name_prefix}-seqr-web"
  retention_in_days = 30

  tags = {
    Name = "${local.name_prefix}-seqr-web-logs"
  }
}

# =============================================================================
# Step 4: Security Groups
# =============================================================================

# ALB Security Group - public-facing, allows HTTP inbound
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Security group for seqr ALB"
  vpc_id      = local.vpc_id

  # Allow HTTP from allowed CIDRs and bastion host
  ingress {
    description = "HTTP from allowed CIDRs and bastion"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = concat(var.allowed_web_cidrs, ["${aws_eip.bastion.public_ip}/32"])
  }

  # Allow outbound to ECS service
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-alb-sg"
  }
}

# ECS Service Security Group - allows traffic from ALB, outbound to Aurora/Clickhouse/ECR
resource "aws_security_group" "ecs_service" {
  name        = "${local.name_prefix}-ecs-service-sg"
  description = "Security group for seqr ECS Fargate service"
  vpc_id      = local.vpc_id

  # Allow inbound from ALB on container port
  ingress {
    description     = "HTTP from ALB"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Allow all outbound (Aurora 5432, Clickhouse 8123/9000, VPC endpoints 443)
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-ecs-service-sg"
  }
}
