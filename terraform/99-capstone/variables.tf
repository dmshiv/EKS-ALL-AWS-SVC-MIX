variable "app_namespace" {
  description = "Namespace the Helm chart deploys CloudCart into (must equal the 08-pod-identity namespace)."
  type        = string
  default     = "cloudcart"
}

variable "image_tag" {
  description = "Immutable image tag to deploy (e.g. v1.0.0-3f2a1c9). Never 'latest'. scripts/build-push.sh prints the tag it pushed."
  type        = string
  default     = "v1.0.0"

  validation {
    condition     = var.image_tag != "latest"
    error_message = "Do not deploy ':latest'. Use an immutable version tag (v1.0.0, git sha, build number)."
  }
}
