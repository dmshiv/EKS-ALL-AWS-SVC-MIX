variable "force_destroy" {
  description = "DESTRUCTIVE: LAB=true lets terraform destroy empty the bucket (all product images and versions are deleted). PRODUCTION=false."
  type        = bool
  default     = true
}
