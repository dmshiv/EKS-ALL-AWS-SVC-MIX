output "controller_role_arn" {
  description = "IAM role of the AWS Load Balancer Controller."
  value       = aws_iam_role.lbc.arn
}

output "helm_release_status" {
  description = "Helm release status."
  value       = helm_release.lbc.status
}
