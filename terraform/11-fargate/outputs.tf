output "fargate_profile_name" {
  description = "Fargate profile name."
  value       = aws_eks_fargate_profile.demo.fargate_profile_name
}

output "fargate_namespace" {
  description = "Namespace scheduled onto Fargate."
  value       = var.fargate_namespace
}
