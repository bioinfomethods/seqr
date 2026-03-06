# Aurora PostgreSQL Module Variables

variable "name_prefix" {
  description = "Name prefix for all resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where Aurora will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for Aurora (must span at least 2 AZs)"
  type        = list(string)
}

variable "bastion_security_group_id" {
  description = "Security group ID of bastion host for PostgreSQL access"
  type        = string
}

variable "instance_class" {
  description = "Instance class for Aurora PostgreSQL"
  type        = string
}

variable "master_username" {
  description = "Master username for Aurora PostgreSQL"
  type        = string
}

variable "master_password" {
  description = "Master password for Aurora PostgreSQL"
  type        = string
  sensitive   = true
}

variable "database_name" {
  description = "Database name for seqr application"
  type        = string
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version"
  type        = string
  default     = "17.6"
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

variable "clickhouse_security_group_id" {
  description = "Security group ID of Clickhouse instance for PostgreSQL access"
  type        = string
  default     = ""
}

variable "ecs_security_group_id" {
  description = "Security group ID of ECS Fargate service for PostgreSQL access"
  type        = string
  default     = ""
}
