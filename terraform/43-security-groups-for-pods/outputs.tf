output "pods_db_security_group_id" {
  description = "Security group id for the SecurityGroupPolicy (kubernetes/security-groups-for-pods)."
  value       = aws_security_group.pods_db.id
}
