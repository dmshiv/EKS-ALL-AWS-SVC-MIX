output "node_security_group_id" {
  description = "Security group attached to all worker nodes (managed node group + Karpenter)."
  value       = aws_security_group.nodes.id
}

output "rds_security_group_id" {
  description = "SG for RDS (ingress 5432 from nodes)."
  value       = aws_security_group.rds.id
}

output "redis_security_group_id" {
  description = "SG for ElastiCache (ingress 6379 from nodes)."
  value       = aws_security_group.redis.id
}

output "efs_security_group_id" {
  description = "SG for EFS mount targets (ingress 2049 from nodes)."
  value       = aws_security_group.efs.id
}
