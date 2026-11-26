output "ssm_prefix" {
  description = "Parameter Store path prefix; set as SSM_PREFIX in the pods."
  value       = local.ssm_prefix
}

output "ssm_prefix_arn" {
  description = "ARN of the prefix (policies)."
  value       = local.ssm_prefix_arn
}
