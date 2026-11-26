output "event_bus_name" {
  description = "Custom event bus name (the worker publishes here)."
  value       = aws_cloudwatch_event_bus.this.name
}

output "event_bus_arn" {
  description = "Custom event bus ARN."
  value       = aws_cloudwatch_event_bus.this.arn
}

output "rule_name" {
  description = "Rule that matches OrderProcessed events."
  value       = aws_cloudwatch_event_rule.order_processed.name
}

output "rule_arn" {
  description = "ARN of the rule (Lambda permission source)."
  value       = aws_cloudwatch_event_rule.order_processed.arn
}

output "events_dlq_arn" {
  description = "Delivery DLQ ARN (target dead_letter_config)."
  value       = aws_sqs_queue.events_dlq.arn
}

output "events_dlq_name" {
  description = "Delivery DLQ name (CloudWatch alarm dimension)."
  value       = aws_sqs_queue.events_dlq.name
}
