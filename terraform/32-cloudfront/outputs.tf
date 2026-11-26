output "enabled" {
  description = "Whether the distribution was created."
  value       = local.enabled
}

output "distribution_id" {
  description = "CloudFront distribution id (for invalidations)."
  value       = local.enabled ? aws_cloudfront_distribution.this[0].id : ""
}

output "distribution_domain" {
  description = "dxxxx.cloudfront.net domain."
  value       = local.enabled ? aws_cloudfront_distribution.this[0].domain_name : ""
}
