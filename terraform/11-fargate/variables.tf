variable "fargate_namespace" {
  description = "Namespace whose pods are scheduled onto Fargate (create it with kubernetes/namespaces/fargate-demo.yaml)."
  type        = string
  default     = "fargate-demo"
}
