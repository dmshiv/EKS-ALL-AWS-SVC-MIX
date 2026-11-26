output "config_bucket" {
  description = "S3 bucket with AWS Config history (empty when disabled)."
  value       = var.enable_config ? aws_s3_bucket.config[0].id : ""
}

output "recorder_name" {
  description = "Config recorder name (empty when disabled)."
  value       = var.enable_config ? aws_config_configuration_recorder.this[0].name : ""
}
