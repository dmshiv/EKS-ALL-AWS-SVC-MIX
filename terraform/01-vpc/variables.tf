variable "vpc_cidr" {
  description = "Primary IPv4 CIDR of the VPC. Must not overlap with on-prem/other VPCs you may peer later."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && tonumber(split("/", var.vpc_cidr)[1]) <= 18
    error_message = "vpc_cidr must be a valid CIDR with a prefix of /18 or larger (pods consume many IPs)."
  }
}

variable "az_count" {
  description = "Number of Availability Zones to span (EKS needs at least 2; production uses 3)."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "single_nat_gateway" {
  description = "LAB: one shared NAT gateway (cheap, single-AZ failure domain). PRODUCTION: false = one NAT per AZ."
  type        = bool
  default     = true
}
