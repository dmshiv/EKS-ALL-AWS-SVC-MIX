output "metrics_server_addon" {
  description = "metrics-server add-on installed."
  value       = aws_eks_addon.metrics_server.addon_name
}

output "cluster_autoscaler_enabled" {
  description = "Whether the Cluster Autoscaler comparison lab is installed."
  value       = var.enable_cluster_autoscaler
}
