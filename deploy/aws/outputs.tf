# Seqr AWS Infrastructure - Outputs

# Networking
output "vpc_id" {
  description = "VPC ID being used"
  value       = local.vpc_id
}

output "subnet_ids" {
  description = "Subnet IDs in the VPC"
  value       = data.aws_subnets.default.ids
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
