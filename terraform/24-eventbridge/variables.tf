variable "event_archive_retention_days" {
  description = "Days EventBridge keeps events for replay (0 = forever). Archives cost per GB stored."
  type        = number
  default     = 3
}
