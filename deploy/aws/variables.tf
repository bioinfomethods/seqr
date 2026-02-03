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
