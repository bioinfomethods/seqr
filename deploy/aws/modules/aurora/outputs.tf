# Aurora PostgreSQL Module Outputs

output "cluster_endpoint" {
  description = "Aurora cluster writer endpoint"
  value       = aws_rds_cluster.seqr.endpoint
}

output "cluster_reader_endpoint" {
  description = "Aurora cluster reader endpoint"
  value       = aws_rds_cluster.seqr.reader_endpoint
}

output "cluster_port" {
  description = "Aurora cluster port"
  value       = aws_rds_cluster.seqr.port
}

output "database_name" {
  description = "Aurora database name"
  value       = aws_rds_cluster.seqr.database_name
}

output "master_username" {
  description = "Aurora master username"
  value       = aws_rds_cluster.seqr.master_username
  sensitive   = true
}

output "security_group_id" {
  description = "Security group ID for Aurora"
  value       = aws_security_group.aurora.id
}

output "cluster_id" {
  description = "Aurora cluster identifier"
  value       = aws_rds_cluster.seqr.id
}
