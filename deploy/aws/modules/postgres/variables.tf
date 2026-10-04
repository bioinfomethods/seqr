# PostgreSQL (RDS) Module Variables

variable "name_prefix" {
  description = "Name prefix for all resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the database will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the DB subnet group (must span at least 2 AZs)"
  type        = list(string)
}

variable "bastion_security_group_id" {
  description = "Security group ID of bastion host for PostgreSQL access"
  type        = string
}

variable "clickhouse_security_group_id" {
  description = "Security group ID of Clickhouse instance for PostgreSQL access"
  type        = string
}

variable "ecs_security_group_id" {
  description = "Security group ID of ECS Fargate service for PostgreSQL access"
  type        = string
}

variable "instance_class" {
  description = "Instance class for RDS PostgreSQL"
  type        = string
}

variable "master_username" {
  description = "Master username for RDS PostgreSQL"
  type        = string
}

variable "master_password" {
  description = "Master password for RDS PostgreSQL"
  type        = string
  sensitive   = true
}

variable "database_name" {
  description = "Database name for seqr application"
  type        = string
}

variable "engine_version" {
  description = "RDS PostgreSQL engine version"
  type        = string
  default     = "17.7"
}

variable "allocated_storage" {
  description = "Initial allocated storage in GB"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Maximum storage in GB for storage autoscaling (must be greater than allocated_storage)"
  type        = number
  default     = 100
}

variable "multi_az" {
  description = "Enable Multi-AZ deployment"
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Backup retention period in days"
  type        = number
  default     = 7
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot when destroying (set to false for production)"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Enable deletion protection on the DB instance (recommended for production)"
  type        = bool
  default     = false
}
