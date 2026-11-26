variable "enable_prefix_delegation_nodegroup" {
  description = "Create a second managed node group (1 x m5.large) configured for prefix delegation (maxPods=110). Requires vpc_cni_prefix_delegation=true in 06-eks. COSTS an EC2 instance while it exists."
  type        = bool
  default     = false
}

variable "instance_types" {
  description = "Nitro instance types for the prefix-delegation node group (prefix delegation requires Nitro)."
  type        = list(string)
  default     = ["m5.large"]
}

variable "max_pods" {
  description = "kubelet maxPods. AWS recommends 110 for instances under 30 vCPUs and 250 above, when prefix delegation is on."
  type        = number
  default     = 110
}
