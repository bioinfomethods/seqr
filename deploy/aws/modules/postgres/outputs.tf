# PostgreSQL (RDS) Module Outputs

output "endpoint" {
  description = "RDS PostgreSQL hostname (address only, without port)"
  value       = aws_db_instance.seqr.address
}

output "port" {
  description = "RDS PostgreSQL port"
  value       = aws_db_instance.seqr.port
}

output "database_name" {
  description = "RDS PostgreSQL database name"
  value       = aws_db_instance.seqr.db_name
}

output "master_username" {
  description = "RDS PostgreSQL master username"
  value       = aws_db_instance.seqr.username
  sensitive   = true
}

output "security_group_id" {
  description = "Security group ID for RDS PostgreSQL"
  value       = aws_security_group.postgres.id
}

output "instance_id" {
  description = "RDS PostgreSQL instance identifier"
  value       = aws_db_instance.seqr.identifier
}
