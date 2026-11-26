variable "enable_securityhub" {
  description = "Enable Security Hub with the AWS Foundational Security Best Practices standard (billed per check). Apply 39-config first. FAILS if Security Hub is already enabled in the account/region."
  type        = bool
  default     = false
}
