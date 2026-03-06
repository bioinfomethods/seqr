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

# =============================================================================
# Step 5: Update Existing Security Groups for ECS Access
# =============================================================================

# Allow ECS service to access Aurora PostgreSQL (port 5432)
resource "aws_security_group_rule" "aurora_from_ecs" {
  type                     = "ingress"
  description              = "PostgreSQL from ECS Fargate service"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_service.id
  security_group_id        = module.aurora.security_group_id
}

# Allow ECS service to access Clickhouse HTTP interface (port 8123)
resource "aws_security_group_rule" "clickhouse_http_from_ecs" {
  type                     = "ingress"
  description              = "Clickhouse HTTP from ECS Fargate service"
  from_port                = 8123
  to_port                  = 8123
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_service.id
  security_group_id        = aws_security_group.clickhouse.id
}

# Allow ECS service to access Clickhouse native protocol (port 9000)
resource "aws_security_group_rule" "clickhouse_native_from_ecs" {
  type                     = "ingress"
  description              = "Clickhouse native from ECS Fargate service"
  from_port                = 9000
  to_port                  = 9000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_service.id
  security_group_id        = aws_security_group.clickhouse.id
}

# =============================================================================
# Step 6: Application Load Balancer
# =============================================================================

# ALB
resource "aws_lb" "seqr" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.seqr_az1.id, aws_subnet.seqr_az2.id]

  tags = {
    Name = "${local.name_prefix}-alb"
  }
}

# Target Group for seqr-web containers
resource "aws_lb_target_group" "seqr_web" {
  name        = "${local.name_prefix}-seqr-web-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/status"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 10
    interval            = 30
    matcher             = "200"
  }

  tags = {
    Name = "${local.name_prefix}-seqr-web-tg"
  }
}

# ALB Listener - HTTP on port 80
resource "aws_lb_listener" "seqr_http" {
  load_balancer_arn = aws_lb.seqr.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.seqr_web.arn
  }

  tags = {
    Name = "${local.name_prefix}-seqr-http-listener"
  }
}

# =============================================================================
# Step 7: ECS Task Definition
# =============================================================================

resource "aws_ecs_task_definition" "seqr_web" {
  family                   = "${local.name_prefix}-seqr-web"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.seqr_web_cpu
  memory                   = var.seqr_web_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([
    {
      name      = "seqr-web"
      image     = "${aws_ecr_repository.seqr_web.repository_url}:${var.seqr_web_image_tag}"
      essential = true

      portMappings = [
        {
          containerPort = 8000
          protocol      = "tcp"
        }
      ]

      environment = [
        # PostgreSQL connection (matches settings.py POSTGRES_DB_CONFIG)
        { name = "POSTGRES_SERVICE_HOSTNAME", value = module.aurora.cluster_endpoint },
        { name = "POSTGRES_SERVICE_PORT", value = tostring(module.aurora.cluster_port) },
        { name = "POSTGRES_USERNAME", value = var.aurora_master_username },
        { name = "POSTGRES_PASSWORD", value = var.aurora_master_password },

        # Gunicorn settings
        { name = "GUNICORN_WORKER_THREADS", value = "4" },

        # Clickhouse connection (matches settings.py CLICKHOUSE_SERVICE_HOSTNAME block)
        { name = "CLICKHOUSE_SERVICE_HOSTNAME", value = aws_instance.clickhouse.private_ip },
        { name = "CLICKHOUSE_SERVICE_PORT", value = "9000" },
        { name = "CLICKHOUSE_WRITER_USER", value = var.clickhouse_writer_user },
        { name = "CLICKHOUSE_WRITER_PASSWORD", value = var.clickhouse_writer_password },
        { name = "CLICKHOUSE_READER_USER", value = var.clickhouse_reader_user },
        { name = "CLICKHOUSE_READER_PASSWORD", value = var.clickhouse_reader_password },

        # Redis connection
        { name = "REDIS_SERVICE_HOSTNAME", value = var.redis_service_hostname },
        { name = "REDIS_SERVICE_PORT", value = tostring(var.redis_service_port) },

        # Django / deployment settings
        # NOTE: DEPLOYMENT_TYPE of "prod" or "dev" enables CSRF_COOKIE_SECURE and
        # SESSION_COOKIE_SECURE which require HTTPS. Using "dev" to avoid loading
        # corsheaders/hijack packages that may not be in the production image.
        # TODO: Add HTTPS via ACM certificate + Route53, then switch to "prod".
        { name = "DEPLOYMENT_TYPE", value = "dev" },
        { name = "BASE_URL", value = "http://${aws_lb.seqr.dns_name}" },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.seqr_web.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "seqr-web"
        }
      }
    }
  ])

  tags = {
    Name = "${local.name_prefix}-seqr-web-task"
  }
}

# =============================================================================
# Step 8: ECS Service
# =============================================================================

resource "aws_ecs_service" "seqr_web" {
  name            = "${local.name_prefix}-seqr-web"
  cluster         = aws_ecs_cluster.seqr.id
  task_definition = aws_ecs_task_definition.seqr_web.arn
  desired_count   = var.seqr_web_desired_count
  launch_type     = "FARGATE"

  # Force redeployment whenever the task definition changes
  force_new_deployment = true

  # Allow time for migrations and startup before health checks begin
  health_check_grace_period_seconds = 300

  network_configuration {
    subnets          = [aws_subnet.seqr_az1.id, aws_subnet.seqr_az2.id]
    security_groups  = [aws_security_group.ecs_service.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.seqr_web.arn
    container_name   = "seqr-web"
    container_port   = 8000
  }

  # Ensure ALB listener is created before the service
  depends_on = [aws_lb_listener.seqr_http]

  tags = {
    Name = "${local.name_prefix}-seqr-web-service"
  }
}
