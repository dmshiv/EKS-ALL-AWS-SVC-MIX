variable "namespace" {
  description = "Application namespace that receives the platform baseline policies. It must already exist (kubectl apply -f kubernetes/namespaces/)."
  type        = string
  default     = "cloudcart"
}
