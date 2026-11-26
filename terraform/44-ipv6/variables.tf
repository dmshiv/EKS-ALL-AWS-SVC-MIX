variable "enable_ipv6_lab" {
  description = "Create the SEPARATE dual-stack lab VPC (free: no NAT, no EC2). The main CloudCart VPC stays IPv4; EKS ip_family is immutable and chosen at cluster creation."
  type        = bool
  default     = false
}

variable "lab_vpc_cidr" {
  description = "IPv4 CIDR of the IPv6 lab VPC (must not overlap the CloudCart VPC)."
  type        = string
  default     = "10.60.0.0/16"
}
