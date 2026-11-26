output "dns_enabled" {
  description = "Whether a domain was configured."
  value       = local.enabled
}

output "domain_name" {
  description = "Root domain (empty when DNS is disabled)."
  value       = var.domain_name
}

output "zone_id" {
  description = "Route 53 hosted zone id (empty when DNS disabled)."
  value       = local.zone_id
}

output "app_fqdn" {
  description = "Public hostname of the application."
  value       = local.app_fqdn
}

output "origin_fqdn" {
  description = "Hostname of the ALB origin behind CloudFront."
  value       = local.origin_fqdn
}

output "name_servers" {
  description = "NS records to set at your registrar when create_hosted_zone=true."
  value       = local.enabled && var.create_hosted_zone ? aws_route53_zone.this[0].name_servers : []
}
