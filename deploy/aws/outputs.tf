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

output "seqr_subnet_id" {
  description = "Dedicated seqr subnet ID"
  value       = aws_subnet.seqr.id
}

output "seqr_subnet_cidr" {
  description = "CIDR block of seqr subnet"
  value       = aws_subnet.seqr.cidr_block
}

output "bastion_security_group_id" {
  description = "Security group ID for bastion host"
  value       = aws_security_group.bastion.id
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
