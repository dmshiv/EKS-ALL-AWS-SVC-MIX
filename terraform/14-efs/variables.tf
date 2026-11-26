variable "efs_throughput_mode" {
  description = "elastic (pay per use, recommended) or bursting."
  type        = string
  default     = "elastic"
}

variable "efs_posix_uid" {
  description = "UID/GID enforced by the EFS access point (must match the pod's runAsUser/fsGroup)."
  type        = number
  default     = 10001
}
