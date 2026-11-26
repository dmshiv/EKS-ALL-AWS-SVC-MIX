output "repository_urls" {
  description = "Repository URL per service (account.dkr.ecr.region.amazonaws.com/name)."
  value       = { for k, v in aws_ecr_repository.this : k => v.repository_url }
}

output "repository_arns" {
  description = "Repository ARN per service."
  value       = { for k, v in aws_ecr_repository.this : k => v.arn }
}

output "registry_url" {
  description = "Registry host used by 'docker login'."
  value       = "${local.account_id}.dkr.ecr.${var.region}.amazonaws.com"
}
