output "deploy_role_arn" {
  description = "Set as the AWS_ROLE_TO_ASSUME variable in GitHub Actions (empty when CI is disabled)."
  value       = local.enabled ? aws_iam_role.deploy[0].arn : ""
}
