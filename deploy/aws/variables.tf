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
  default     = "172.31.254.0/28"  # 16 IP addresses
}

variable "subnet_cidr_az2" {
  description = "CIDR block for the seqr subnet in AZ2"
  type        = string
  default     = "172.31.254.16/28"  # 16 IP addresses
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
