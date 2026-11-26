variable "system_instance_types" {
  description = "Instance types of the system managed node group. LAB: t3.medium (cheap, burstable)."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "system_capacity_type" {
  description = "ON_DEMAND (default, stable) or SPOT (cheaper, can be interrupted). System components (CoreDNS, Karpenter) belong on ON_DEMAND."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.system_capacity_type)
    error_message = "system_capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "system_desired_size" {
  description = "Initial node count (Terraform ignores later changes so autoscaling is not fought)."
  type        = number
  default     = 2
}

variable "system_min_size" {
  description = "Minimum nodes."
  type        = number
  default     = 2
}

variable "system_max_size" {
  description = "Maximum nodes."
  type        = number
  default     = 3
}

variable "system_disk_size_gb" {
  description = "Root EBS volume size (GiB)."
  type        = number
  default     = 30
}

variable "taint_system_nodes" {
  description = "Taint system nodes with CriticalAddonsOnly so ONLY addons/Karpenter run there (apps must then use Karpenter nodes). LAB default false for reliability."
  type        = bool
  default     = false
}
