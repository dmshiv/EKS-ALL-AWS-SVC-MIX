output "orders_queue_url" {
  description = "URL of the orders queue (used by order-service and worker)."
  value       = aws_sqs_queue.orders.url
}

output "orders_queue_arn" {
  description = "ARN of the orders queue."
  value       = aws_sqs_queue.orders.arn
}

output "orders_queue_name" {
  description = "Name of the orders queue (CloudWatch dimension)."
  value       = aws_sqs_queue.orders.name
}

output "dlq_arn" {
  description = "ARN of the dead-letter queue."
  value       = aws_sqs_queue.dlq.arn
}

output "dlq_name" {
  description = "Name of the dead-letter queue (CloudWatch dimension)."
  value       = aws_sqs_queue.dlq.name
}
