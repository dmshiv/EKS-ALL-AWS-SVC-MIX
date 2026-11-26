variable "deletion_window_in_days" {
  description = "Waiting period before a scheduled key deletion takes effect (7-30). LAB=7, PRODUCTION=30."
  type        = number
  default     = 7

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days must be between 7 and 30."
  }
}
