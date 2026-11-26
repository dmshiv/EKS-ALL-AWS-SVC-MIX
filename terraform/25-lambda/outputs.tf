output "lambda_function_name" {
  description = "Notifier Lambda name."
  value       = aws_lambda_function.notifier.function_name
}

output "lambda_function_arn" {
  description = "Notifier Lambda ARN."
  value       = aws_lambda_function.notifier.arn
}

output "lambda_log_group" {
  description = "CloudWatch log group of the function."
  value       = aws_cloudwatch_log_group.notifier.name
}
