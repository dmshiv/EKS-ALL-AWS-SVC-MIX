variable "namespaces" {
  description = "Namespaces whose ServiceAccount 'irsa-demo' may assume the demo role (cloudcart for EC2 nodes, fargate-demo for Fargate)."
  type        = list(string)
  default     = ["cloudcart", "fargate-demo"]
}

variable "service_account_name" {
  description = "ServiceAccount name allowed to assume the IRSA demo role."
  type        = string
  default     = "irsa-demo"
}
