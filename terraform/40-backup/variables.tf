variable "retention_days" {
  description = "Days daily recovery points are kept."
  type        = number
  default     = 7
}

variable "enable_cross_region_copy" {
  description = "Copy every recovery point to a vault in dr_region (disaster recovery). Adds storage + transfer cost."
  type        = bool
  default     = false
}

variable "dr_region" {
  description = "Region of the DR vault (only used when enable_cross_region_copy=true). Must differ from the primary region."
  type        = string
  default     = "us-west-2"
}

variable "force_destroy_vault" {
  description = "DESTRUCTIVE: LAB=true deletes the vault even if it contains recovery points. PRODUCTION=false (and consider Vault Lock)."
  type        = bool
  default     = true
}
