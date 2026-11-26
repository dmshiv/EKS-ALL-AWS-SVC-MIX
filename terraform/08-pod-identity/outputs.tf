output "role_names" {
  description = "Workload role NAME per ServiceAccount (data folders attach their least-privilege inline policies to these)."
  value       = { for k, v in aws_iam_role.workload : k => v.name }
}

output "role_arns" {
  description = "Workload role ARN per ServiceAccount."
  value       = { for k, v in aws_iam_role.workload : k => v.arn }
}

output "namespace" {
  description = "Namespace the associations are bound to."
  value       = var.namespace
}
