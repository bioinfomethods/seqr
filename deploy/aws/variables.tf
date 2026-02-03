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

variable "subnet_cidr" {
  description = "CIDR block for the seqr subnet"
  type        = string
  default     = "172.31.255.0/28"  # 16 IP addresses
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
