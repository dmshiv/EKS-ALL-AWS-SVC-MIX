variable "rate_limit_per_5min" {
  description = "Rate-based rule: max requests per client IP in a 5-minute window before it is blocked (min 10)."
  type        = number
  default     = 2000
}

variable "managed_rules_action" {
  description = "none = the managed rule groups BLOCK (production). count = they only COUNT (observe-first rollout, avoids blocking real users while tuning)."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "count"], var.managed_rules_action)
    error_message = "managed_rules_action must be none (enforce) or count (observe)."
  }
}

variable "log_retention_days" {
  description = "Retention of the WAF log group."
  type        = number
  default     = 7
}
