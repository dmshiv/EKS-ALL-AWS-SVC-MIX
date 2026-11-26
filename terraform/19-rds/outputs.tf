output "db_address" {
  description = "RDS DNS name (resolves to a private IP inside the VPC)."
  value       = aws_db_instance.this.address
}

output "db_port" {
  description = "RDS port."
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Initial database name."
  value       = aws_db_instance.this.db_name
}

output "db_identifier" {
  description = "RDS instance identifier."
  value       = aws_db_instance.this.identifier
}

output "db_arn" {
  description = "RDS instance ARN (AWS Backup selection)."
  value       = aws_db_instance.this.arn
}
