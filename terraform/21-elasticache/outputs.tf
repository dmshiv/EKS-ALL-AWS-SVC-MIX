output "primary_endpoint" {
  description = "Primary endpoint DNS name."
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "port" {
  description = "Cache port."
  value       = aws_elasticache_replication_group.this.port
}

output "replication_group_id" {
  description = "Replication group id."
  value       = aws_elasticache_replication_group.this.id
}
