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
