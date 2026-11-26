output "alb_certificate_arn" {
  description = "ACM certificate ARN for the ALB (empty when DNS disabled)."
  value       = local.enabled ? aws_acm_certificate_validation.regional[0].certificate_arn : ""
}

output "cloudfront_certificate_arn" {
  description = "ACM certificate ARN usable by CloudFront (us-east-1)."
  value       = !local.enabled ? "" : (local.need_global_cert ? aws_acm_certificate_validation.global[0].certificate_arn : aws_acm_certificate_validation.regional[0].certificate_arn)
}
