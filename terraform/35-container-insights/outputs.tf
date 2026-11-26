output "addon_name" {
  description = "Installed observability add-on."
  value       = aws_eks_addon.observability.addon_name
}

output "log_group_prefix" {
  description = "Container Insights log group prefix."
  value       = "/aws/containerinsights/${local.cluster_name}"
}
