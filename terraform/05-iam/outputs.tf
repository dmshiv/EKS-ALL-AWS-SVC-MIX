output "cluster_role_arn" {
  description = "IAM role of the EKS control plane."
  value       = aws_iam_role.cluster.arn
}

output "cluster_role_name" {
  description = "Name of the cluster role (06-eks attaches its KMS inline policy here)."
  value       = aws_iam_role.cluster.name
}

output "node_role_arn" {
  description = "IAM role of managed-node-group nodes."
  value       = aws_iam_role.node.arn
}

output "node_role_name" {
  description = "Name of the node role."
  value       = aws_iam_role.node.name
}

output "fargate_role_arn" {
  description = "Pod execution role for the Fargate profile."
  value       = aws_iam_role.fargate.arn
}
