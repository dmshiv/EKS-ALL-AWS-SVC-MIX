variable "ebs_csi_addon_version" {
  description = "Pin the aws-ebs-csi-driver add-on version (e.g. v1.45.0-eksbuild.1). null = the default version for the cluster's Kubernetes minor."
  type        = string
  default     = null
}
