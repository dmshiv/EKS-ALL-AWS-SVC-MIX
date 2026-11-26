variable "extra_admin_principal_arns" {
  description = "Additional IAM role/user ARNs that get cluster-admin through access entries (e.g. your SSO admin role). The Terraform caller already is admin via bootstrap_cluster_creator_admin_permissions."
  type        = list(string)
  default     = []
}

variable "developer_namespace" {
  description = "Namespace where the demo developer role may edit workloads."
  type        = string
  default     = "cloudcart"
}
