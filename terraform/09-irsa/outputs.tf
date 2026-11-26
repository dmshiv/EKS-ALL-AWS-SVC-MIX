output "irsa_demo_role_arn" {
  description = "Annotate ServiceAccount irsa-demo with eks.amazonaws.com/role-arn = this value."
  value       = aws_iam_role.irsa_demo.arn
}

output "irsa_demo_role_name" {
  description = "Role name (15-s3 attaches the bucket-list policy here)."
  value       = aws_iam_role.irsa_demo.name
}
