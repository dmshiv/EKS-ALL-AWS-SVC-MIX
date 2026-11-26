output "eip_allocation_ids" {
  description = "Comma-separated EIP allocation ids for the annotation service.beta.kubernetes.io/aws-load-balancer-eip-allocations (order matches public_subnet_ids)."
  value       = join(",", [for az in local.azs : aws_eip.nlb[az].id if var.enable_static_ips])
}

output "public_ips" {
  description = "The static public IPs customers can allow-list."
  value       = [for az in local.azs : aws_eip.nlb[az].public_ip if var.enable_static_ips]
}

output "public_subnet_ids" {
  description = "Subnets for the annotation aws-load-balancer-subnets (same order as the EIPs)."
  value       = local.public_subnet_ids
}
