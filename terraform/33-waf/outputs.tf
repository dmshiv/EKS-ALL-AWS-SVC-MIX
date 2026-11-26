output "web_acl_arn" {
  description = "ARN to put in the Ingress annotation alb.ingress.kubernetes.io/wafv2-acl-arn."
  value       = aws_wafv2_web_acl.alb.arn
}

output "web_acl_name" {
  description = "Web ACL name (CloudWatch metrics dimension)."
  value       = aws_wafv2_web_acl.alb.name
}

output "waf_log_group" {
  description = "CloudWatch log group with WAF decisions."
  value       = aws_cloudwatch_log_group.waf.name
}
