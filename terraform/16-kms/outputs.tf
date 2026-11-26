output "eks_secrets_key_arn" {
  description = "KMS key for EKS Kubernetes Secrets envelope encryption."
  value       = aws_kms_key.eks_secrets.arn
}

output "data_key_arn" {
  description = "KMS key for application data at rest."
  value       = aws_kms_key.data.arn
}

output "data_key_id" {
  description = "Key id of the data key."
  value       = aws_kms_key.data.key_id
}

output "data_key_alias" {
  description = "Alias of the data key."
  value       = aws_kms_alias.data.name
}
