variable "kubernetes_version" {
  description = "EKS Kubernetes minor version. Use a version still in STANDARD support (extended support costs ~6x more control-plane $). Verify: aws eks describe-cluster-versions."
  type        = string
  default     = "1.35"
}

variable "endpoint_public_access" {
  description = "LAB=true so you can run kubectl/helm from your workstation. PRODUCTION=false (private endpoint + VPN/bastion/CI inside the VPC)."
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the PUBLIC API endpoint. Restrict to your IP/32 (curl -s ifconfig.me) for anything beyond a throwaway lab."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cluster_log_types" {
  description = "Control-plane log types sent to CloudWatch Logs (each type adds ingestion cost). Options: api, audit, authenticator, controllerManager, scheduler."
  type        = list(string)
  default     = ["api", "audit", "authenticator"]
}

variable "log_retention_days" {
  description = "Retention for the control-plane log group. Never leave log groups at 'never expire'."
  type        = number
  default     = 7
}

variable "vpc_cni_prefix_delegation" {
  description = "Assign /28 prefixes (16 IPs) per ENI slot instead of single IPs: ~10x more pods per node. Needs Nitro instances. See docs/networking."
  type        = bool
  default     = false
}

variable "vpc_cni_pod_eni" {
  description = "Enable Security Groups for Pods (trunk/branch ENIs). Needs supported instance types (m5/c5/r5...; NOT t3)."
  type        = bool
  default     = false
}

variable "vpc_cni_network_policy" {
  description = "Enable the VPC CNI built-in NetworkPolicy agent (eBPF). Required for kubernetes/network-policies to be enforced."
  type        = bool
  default     = true
}

variable "ip_family" {
  description = "ipv4 (default) or ipv6. IMMUTABLE after creation. ipv6 needs a dual-stack VPC (see 44-ipv6 for the design and lab)."
  type        = string
  default     = "ipv4"

  validation {
    condition     = contains(["ipv4", "ipv6"], var.ip_family)
    error_message = "ip_family must be ipv4 or ipv6."
  }
}
