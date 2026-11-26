variable "enable_cluster_autoscaler" {
  description = "Install the Kubernetes Cluster Autoscaler for the managed node group (COMPARISON LAB). Do not run it together with Karpenter on the same capacity: pick one node autoscaler per pool."
  type        = bool
  default     = false
}

variable "cluster_autoscaler_chart_version" {
  description = "cluster-autoscaler Helm chart version (kubernetes/autoscaler)."
  type        = string
  default     = "9.46.6"
}
