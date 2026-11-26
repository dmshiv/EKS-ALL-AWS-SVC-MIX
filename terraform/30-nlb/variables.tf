variable "enable_static_ips" {
  description = "Allocate one Elastic IP per AZ for an internet-facing NLB (static IPs customers can allow-list). Each EIP costs ~$3.65/month (public IPv4 charge) even when unused."
  type        = bool
  default     = true
}
