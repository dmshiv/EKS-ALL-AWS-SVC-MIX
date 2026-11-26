variable "db_username" {
  description = "RDS master username stored in the secret (the PASSWORD is generated, never typed or committed)."
  type        = string
  default     = "cloudcart_admin"
}

variable "recovery_window_in_days" {
  description = "Days a deleted secret can still be restored. LAB=0 (immediate delete so names can be reused). PRODUCTION=7-30."
  type        = number
  default     = 0

  validation {
    condition     = var.recovery_window_in_days == 0 || (var.recovery_window_in_days >= 7 && var.recovery_window_in_days <= 30)
    error_message = "recovery_window_in_days must be 0 or between 7 and 30."
  }
}
