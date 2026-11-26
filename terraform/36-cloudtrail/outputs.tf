output "trail_name" {
  description = "CloudTrail trail name (empty when disabled)."
  value       = var.enable_cloudtrail ? aws_cloudtrail.this[0].name : ""
}

output "trail_bucket" {
  description = "S3 bucket holding the audit logs."
  value       = var.enable_cloudtrail ? aws_s3_bucket.trail[0].id : ""
}
