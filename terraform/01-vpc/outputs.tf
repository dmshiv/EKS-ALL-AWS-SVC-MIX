output "vpc_id" {
  description = "VPC id."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC CIDR."
  value       = aws_vpc.this.cidr_block
}

output "azs" {
  description = "Availability zones in use."
  value       = local.azs
}

output "public_subnet_ids" {
  description = "Public subnet ids (ALB/NLB, NAT)."
  value       = [for az in local.azs : aws_subnet.public[az].id]
}

output "private_subnet_ids" {
  description = "Private subnet ids (nodes + pods)."
  value       = [for az in local.azs : aws_subnet.private[az].id]
}

output "private_subnet_ids_by_az" {
  description = "Private subnet id keyed by AZ (used for per-AZ resources, e.g. VPC CNI custom networking)."
  value       = { for az in local.azs : az => aws_subnet.private[az].id }
}

output "private_subnet_cidrs" {
  description = "Private subnet CIDRs."
  value       = [for az in local.azs : aws_subnet.private[az].cidr_block]
}

output "database_subnet_ids" {
  description = "Isolated database subnet ids."
  value       = [for az in local.azs : aws_subnet.database[az].id]
}

output "private_route_table_ids" {
  description = "Private route table ids (gateway endpoints attach here)."
  value       = [for az in local.azs : aws_route_table.private[az].id]
}

output "database_route_table_id" {
  description = "Database route table id."
  value       = aws_route_table.database.id
}

output "nat_public_ips" {
  description = "Egress IPs of the NAT gateway(s); allow-list these at third parties."
  value       = [for eip in aws_eip.nat : eip.public_ip]
}
