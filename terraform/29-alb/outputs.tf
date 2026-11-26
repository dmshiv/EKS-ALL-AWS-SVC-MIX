output "access_logs_bucket" {
  description = "Bucket for ALB access logs (Ingress annotation access_logs.s3.bucket)."
  value       = aws_s3_bucket.alb_logs.id
}

output "access_logs_prefix" {
  description = "Prefix to use in the Ingress annotation (access_logs.s3.prefix)."
  value       = "alb"
}
