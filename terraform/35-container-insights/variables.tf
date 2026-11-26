variable "log_retention_days" {
  description = "Retention for Container Insights log groups (never leave them at 'never expire')."
  type        = number
  default     = 7
}
