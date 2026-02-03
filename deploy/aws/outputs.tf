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

output "bastion_ssh_command" {
  description = "SSH command to connect to bastion host"
  value       = "ssh -i ~/.ssh/${var.bastion_key_name} ec2-user@${aws_eip.bastion.public_ip}"
}

# Aurora PostgreSQL
output "aurora_cluster_endpoint" {
  description = "Aurora cluster writer endpoint"
  value       = aws_rds_cluster.seqr.endpoint
}

output "aurora_cluster_reader_endpoint" {
  description = "Aurora cluster reader endpoint"
  value       = aws_rds_cluster.seqr.reader_endpoint
}

output "aurora_cluster_port" {
  description = "Aurora cluster port"
  value       = aws_rds_cluster.seqr.port
}

output "aurora_database_name" {
  description = "Aurora database name"
  value       = aws_rds_cluster.seqr.database_name
}

output "aurora_master_username" {
  description = "Aurora master username"
  value       = aws_rds_cluster.seqr.master_username
  sensitive   = true
}

output "aurora_security_group_id" {
  description = "Security group ID for Aurora"
  value       = aws_security_group.aurora.id
}

output "aurora_psql_command" {
  description = "Command to connect to Aurora from bastion (password required)"
  value       = "psql -h ${aws_rds_cluster.seqr.endpoint} -U ${var.aurora_master_username} -d ${var.aurora_database_name}"
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
