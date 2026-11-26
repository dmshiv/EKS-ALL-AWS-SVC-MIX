variable "enable_guardduty" {
  description = "Enable GuardDuty with EKS audit-log monitoring. FAILS if a detector already exists in the region (check: aws guardduty list-detectors)."
  type        = bool
  default     = true
}

variable "enable_guardduty_runtime" {
  description = "Also enable EKS Runtime Monitoring (agent per node, billed per vCPU-hour). Off by default."
  type        = bool
  default     = false
}
