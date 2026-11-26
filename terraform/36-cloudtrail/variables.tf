variable "enable_cloudtrail" {
  description = "Create a multi-region management-event trail to S3. The FIRST management trail per account is free; extra trails cost. Set false if the account already has an organisation trail."
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "DESTRUCTIVE: LAB=true lets destroy delete the audit-log bucket with its contents. PRODUCTION=false (audit logs must survive)."
  type        = bool
  default     = true
}

variable "log_expiration_days" {
  description = "Days before CloudTrail objects expire (cost control)."
  type        = number
  default     = 90
}
