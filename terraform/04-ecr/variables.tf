variable "services" {
  description = "CloudCart services that get an ECR repository."
  type        = set(string)
  default     = ["frontend", "product-service", "order-service", "worker"]
}

variable "force_delete" {
  description = "DESTRUCTIVE: LAB=true lets terraform destroy remove repos that still contain images. PRODUCTION=false."
  type        = bool
  default     = true
}

variable "keep_last_images" {
  description = "Lifecycle: number of tagged images to keep per repository."
  type        = number
  default     = 30
}
