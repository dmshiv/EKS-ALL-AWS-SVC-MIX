variable "lambda_runtime" {
  description = "Lambda runtime for the notifier."
  type        = string
  default     = "python3.12"
}

variable "lambda_timeout_seconds" {
  description = "Lambda timeout."
  type        = number
  default     = 15
}

variable "log_retention_days" {
  description = "Retention of the Lambda log group."
  type        = number
  default     = 7
}
