# Seqr AWS Infrastructure - Outputs

# Networking
output "vpc_id" {
  description = "VPC ID being used"
  value       = local.vpc_id
}

output "subnet_ids" {
  description = "Default subnet IDs in the VPC"
  value       = data.aws_subnets.default.ids
}

output "seqr_subnet_az1_id" {
  description = "Dedicated seqr subnet ID in AZ1"
  value       = aws_subnet.seqr_az1.id
}

output "seqr_subnet_az2_id" {
  description = "Dedicated seqr subnet ID in AZ2"
  value       = aws_subnet.seqr_az2.id
}

output "seqr_subnet_az1_cidr" {
  description = "CIDR block of seqr subnet in AZ1"
  value       = aws_subnet.seqr_az1.cidr_block
}

output "seqr_subnet_az2_cidr" {
  description = "CIDR block of seqr subnet in AZ2"
  value       = aws_subnet.seqr_az2.cidr_block
}

output "bastion_security_group_id" {
  description = "Security group ID for bastion host"
  value       = aws_security_group.bastion.id
}

# Bastion Host
output "bastion_public_ip" {
  description = "Public IP address of bastion host"
  value       = aws_eip.bastion.public_ip
}

output "bastion_instance_id" {
  description = "Instance ID of bastion host"
  value       = aws_instance.bastion.id
}

output "bastion_private_ip" {
  description = "Private IP address of bastion host"
  value       = aws_instance.bastion.private_ip
}

output "bastion_ssh_command" {
  description = "SSH command to connect to bastion host"
  value       = "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ~/.ssh/${var.bastion_key_name} ec2-user@${aws_eip.bastion.public_ip}"
}

# Aurora PostgreSQL
output "aurora_cluster_endpoint" {
  description = "Aurora cluster writer endpoint"
  value       = module.aurora.cluster_endpoint
}

output "aurora_cluster_reader_endpoint" {
  description = "Aurora cluster reader endpoint"
  value       = module.aurora.cluster_reader_endpoint
}

output "aurora_cluster_port" {
  description = "Aurora cluster port"
  value       = module.aurora.cluster_port
}

output "aurora_database_name" {
  description = "Aurora database name"
  value       = module.aurora.database_name
}

output "aurora_master_username" {
  description = "Aurora master username"
  value       = module.aurora.master_username
  sensitive   = true
}

output "aurora_security_group_id" {
  description = "Security group ID for Aurora"
  value       = module.aurora.security_group_id
}

output "aurora_psql_command" {
  description = "Command to connect to Aurora from bastion (password required)"
  value       = "psql -h ${module.aurora.cluster_endpoint} -U ${var.aurora_master_username} -d ${var.aurora_database_name}"
}

# ECR
output "ecr_repository_seqr_web_url" {
  description = "ECR repository URL for seqr-web (Django) image"
  value       = aws_ecr_repository.seqr_web.repository_url
}

output "ecr_repository_seqr_web_arn" {
  description = "ECR repository ARN for seqr-web (Django) image"
  value       = aws_ecr_repository.seqr_web.arn
}

output "ecr_repository_clickhouse_url" {
  description = "ECR repository URL for Clickhouse image"
  value       = aws_ecr_repository.clickhouse.repository_url
}

output "ecr_repository_clickhouse_arn" {
  description = "ECR repository ARN for Clickhouse image"
  value       = aws_ecr_repository.clickhouse.arn
}

# Clickhouse
output "clickhouse_data_volume_id" {
  description = "EBS volume ID for ClickHouse data"
  value       = aws_ebs_volume.clickhouse_data.id
}

output "clickhouse_private_ip" {
  description = "Private IP address of Clickhouse instance"
  value       = aws_instance.clickhouse.private_ip
}

output "clickhouse_instance_id" {
  description = "Instance ID of Clickhouse instance"
  value       = aws_instance.clickhouse.id
}

output "clickhouse_security_group_id" {
  description = "Security group ID for Clickhouse"
  value       = aws_security_group.clickhouse.id
}

output "clickhouse_http_endpoint" {
  description = "Clickhouse HTTP endpoint (accessible from bastion)"
  value       = "http://${aws_instance.clickhouse.private_ip}:8123"
}

output "clickhouse_ami_id" {
  description = "AMI ID used for Clickhouse instance"
  value       = aws_instance.clickhouse.ami
}

output "clickhouse_ami_name" {
  description = "AMI name used for Clickhouse instance"
  value       = try(data.aws_ami.clickhouse_custom.name, data.aws_ami.amazon_linux_2023.name)
}

# VPC Endpoints
output "vpc_endpoint_ecr_api_id" {
  description = "VPC Endpoint ID for ECR API"
  value       = aws_vpc_endpoint.ecr_api.id
}

output "vpc_endpoint_ecr_dkr_id" {
  description = "VPC Endpoint ID for ECR Docker"
  value       = aws_vpc_endpoint.ecr_dkr.id
}

output "vpc_endpoint_logs_id" {
  description = "VPC Endpoint ID for CloudWatch Logs"
  value       = aws_vpc_endpoint.logs.id
}

output "vpc_endpoint_s3_id" {
  description = "VPC Endpoint ID for S3"
  value       = aws_vpc_endpoint.s3.id
}

# ECS Fargate / ALB
output "alb_dns_name" {
  description = "DNS name of the seqr ALB"
  value       = aws_lb.seqr.dns_name
}

output "alb_url" {
  description = "URL to access seqr web application"
  value       = "http://${aws_lb.seqr.dns_name}"
}

output "alb_arn" {
  description = "ARN of the seqr ALB"
  value       = aws_lb.seqr.arn
}

# ECS Fargate
output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.seqr.name
}

output "ecs_cluster_arn" {
  description = "ECS cluster ARN"
  value       = aws_ecs_cluster.seqr.arn
}

output "ecs_service_name" {
  description = "ECS service name for seqr-web"
  value       = aws_ecs_service.seqr_web.name
}

output "ecs_task_definition_arn" {
  description = "ECS task definition ARN for seqr-web"
  value       = aws_ecs_task_definition.seqr_web.arn
}

# S3
output "seqr_data_bucket_name" {
  description = "S3 bucket name for seqr application data"
  value       = aws_s3_bucket.seqr_data.bucket
}

output "seqr_data_bucket_arn" {
  description = "S3 bucket ARN for seqr application data"
  value       = aws_s3_bucket.seqr_data.arn
}

# Tagging
output "name_prefix" {
  description = "Name prefix used for all resources"
  value       = local.name_prefix
}

output "default_tags" {
  description = "Default tags applied to all resources"
  value       = local.default_tags
}
