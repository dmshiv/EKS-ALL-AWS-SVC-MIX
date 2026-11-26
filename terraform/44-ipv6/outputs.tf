output "lab_vpc_id" {
  description = "IPv6 lab VPC id (empty when disabled)."
  value       = var.enable_ipv6_lab ? aws_vpc.lab[0].id : ""
}

output "lab_ipv6_cidr" {
  description = "Amazon-provided IPv6 /56 of the lab VPC."
  value       = var.enable_ipv6_lab ? aws_vpc.lab[0].ipv6_cidr_block : ""
}
