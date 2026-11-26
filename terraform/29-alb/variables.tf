variable "log_retention_days" {
  description = "Days ALB access logs are kept in S3 before expiry."
  type        = number
  default     = 14
}

variable "use_legacy_elb_account" {
  description = "true for regions launched before Aug 2022 (e.g. us-east-1, eu-west-1, ap-south-1): ALB logs are delivered by a per-region ELB account principal. false for newer regions (service principal logdelivery.elasticloadbalancing.amazonaws.com)."
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "DESTRUCTIVE: LAB=true lets terraform destroy delete the log bucket even when it contains logs."
  type        = bool
  default     = true
}
