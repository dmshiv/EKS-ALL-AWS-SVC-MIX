output "readonly_role_arn" {
  description = "Role with cluster-wide read-only access (assume it to test Unauthorized/Forbidden behaviour)."
  value       = aws_iam_role.access["readonly"].arn
}

output "developer_role_arn" {
  description = "Role with edit access limited to the cloudcart namespace."
  value       = aws_iam_role.access["developer"].arn
}
