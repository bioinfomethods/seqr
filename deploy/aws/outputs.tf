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

# Tagging
output "name_prefix" {
  description = "Name prefix used for all resources"
  value       = local.name_prefix
}

output "default_tags" {
  description = "Default tags applied to all resources"
  value       = local.default_tags
}
