variable "enable_config" {
  description = "Enable the AWS Config recorder (billed per configuration item recorded). FAILS if a recorder already exists in the region."
  type        = bool
  default     = false
}

variable "force_destroy" {
  description = "DESTRUCTIVE: LAB=true lets destroy delete the Config bucket with recorded history."
  type        = bool
  default     = true
}

variable "log_expiration_days" {
  description = "Days before Config snapshot objects expire (cost control)."
  type        = number
  default     = 90
}
