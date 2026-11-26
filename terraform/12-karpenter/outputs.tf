output "node_role_name" {
  description = "IAM role name Karpenter-launched nodes use (referenced by EC2NodeClass.spec.role)."
  value       = aws_iam_role.node.name
}

output "node_role_arn" {
  description = "IAM role ARN of Karpenter nodes."
  value       = aws_iam_role.node.arn
}

output "controller_role_arn" {
  description = "IAM role of the Karpenter controller."
  value       = aws_iam_role.controller.arn
}

output "interruption_queue_name" {
  description = "SQS queue for Spot/health/state-change events."
  value       = aws_sqs_queue.interruption.name
}
