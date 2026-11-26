output "table_name" {
  description = "Products table name."
  value       = aws_dynamodb_table.products.name
}

output "table_arn" {
  description = "Products table ARN."
  value       = aws_dynamodb_table.products.arn
}
