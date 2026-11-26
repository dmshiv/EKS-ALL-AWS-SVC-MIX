output "topic_arn" {
  description = "SNS topic ARN."
  value       = aws_sns_topic.orders.arn
}

output "notifications_queue_url" {
  description = "URL of the subscriber queue (poll it to see fan-out)."
  value       = aws_sqs_queue.notifications.url
}

output "notifications_queue_arn" {
  description = "ARN of the subscriber queue."
  value       = aws_sqs_queue.notifications.arn
}
