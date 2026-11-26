output "rds_secret_arn" {
  description = "Secrets Manager secret with the RDS credentials."
  value       = aws_secretsmanager_secret.rds.arn
}

output "redis_secret_arn" {
  description = "Secrets Manager secret with the Redis AUTH token."
  value       = aws_secretsmanager_secret.redis.arn
}

output "db_username" {
  description = "Master username."
  value       = var.db_username
}

# Marked sensitive so it is not printed. 19-rds and 21-elasticache read it through remote state.
output "rds_password" {
  description = "Generated RDS master password (sensitive)."
  value       = random_password.rds.result
  sensitive   = true
}

output "redis_auth_token" {
  description = "Generated ElastiCache AUTH token (sensitive)."
  value       = random_password.redis.result
  sensitive   = true
}
