# Seqr AWS Infrastructure - Variables

# Core Configuration
variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "ap-southeast-2"
}

variable "prefix" {
  description = "Prefix for resource naming (e.g., 'myorg')"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, test, prod)"
  type        = string
  
  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, prod"
  }
}

variable "cost_centre" {
  description = "Cost centre tag for billing"
  type        = string
}

# Networking
variable "vpc_id" {
  description = "VPC ID (leave empty to use default VPC)"
  type        = string
  default     = ""
}

variable "subnet_cidr_az1" {
  description = "CIDR block for the seqr subnet in AZ1"
  type        = string
  default     = "172.31.252.0/24"  # 256 IP addresses
}

variable "subnet_cidr_az2" {
  description = "CIDR block for the seqr subnet in AZ2"
  type        = string
  default     = "172.31.253.0/24"  # 256 IP addresses
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH to bastion host"
  type        = list(string)
  default     = []
}

# Bastion Host
variable "bastion_instance_type" {
  description = "EC2 instance type for bastion host"
  type        = string
  default     = "t3.micro"
}

variable "bastion_key_name" {
  description = "SSH key pair name for bastion host"
  type        = string
}

variable "bastion_ami_id" {
  description = "AMI ID for bastion instance (leave empty to use latest Amazon Linux 2023)"
  type        = string
  default     = ""
}

# Aurora PostgreSQL
variable "aurora_instance_class" {
  description = "Instance class for Aurora PostgreSQL"
  type        = string
  default     = "db.t3.medium"
}

variable "aurora_master_username" {
  description = "Master username for Aurora PostgreSQL"
  type        = string
  default     = "seqr"
}

variable "aurora_master_password" {
  description = "Master password for Aurora PostgreSQL"
  type        = string
  sensitive   = true
}

variable "aurora_database_name" {
  description = "Database name for seqr application"
  type        = string
  default     = "seqrdb"
}

variable "aurora_backup_retention_period" {
  description = "Backup retention period in days"
  type        = number
  default     = 7
}

variable "aurora_skip_final_snapshot" {
  description = "Skip final snapshot when destroying (set to false for production)"
  type        = bool
  default     = true
}

# ECS Fargate / ALB
variable "allowed_web_cidrs" {
  description = "CIDR blocks allowed to access the seqr web application via ALB (bastion EIP is always included)"
  type        = list(string)
  default     = []
}

# ECS Fargate / seqr-web
variable "seqr_web_desired_count" {
  description = "Number of seqr-web Fargate tasks to run"
  type        = number
  default     = 1
}

variable "seqr_web_cpu" {
  description = "CPU units for seqr-web Fargate task (256 = 0.25 vCPU, 512 = 0.5 vCPU, 1024 = 1 vCPU)"
  type        = number
  default     = 512
}

variable "seqr_web_memory" {
  description = "Memory in MiB for seqr-web Fargate task"
  type        = number
  default     = 1024
}

variable "seqr_web_image_tag" {
  description = "Docker image tag for seqr-web in ECR"
  type        = string
  default     = "latest"
}

variable "redis_service_hostname" {
  description = "Hostname for Redis service (used by seqr for caching)"
  type        = string
  default     = "localhost"
}

variable "redis_service_port" {
  description = "Port for Redis service"
  type        = number
  default     = 6379
}

# Clickhouse EC2
variable "clickhouse_writer_user" {
  description = "Clickhouse writer username for seqr"
  type        = string
  default     = "default"
}

variable "clickhouse_writer_password" {
  description = "Clickhouse writer password for seqr"
  type        = string
  sensitive   = true
  default     = ""
}

variable "clickhouse_reader_user" {
  description = "Clickhouse reader username for seqr"
  type        = string
  default     = "default"
}

variable "clickhouse_reader_password" {
  description = "Clickhouse reader password for seqr"
  type        = string
  sensitive   = true
  default     = ""
}

variable "clickhouse_instance_type" {
  description = "EC2 instance type for Clickhouse"
  type        = string
  default     = "t3.medium"
}

variable "clickhouse_ami_id" {
  description = "AMI ID for Clickhouse instance (leave empty to use latest Amazon Linux 2023)"
  type        = string
  default     = ""
}

variable "clickhouse_volume_size" {
  description = "EBS volume size in GB for Clickhouse data"
  type        = number
  default     = 100
}

variable "clickhouse_key_name" {
  description = "SSH key pair name for Clickhouse instance"
  type        = string
}
