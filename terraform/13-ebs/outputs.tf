output "ebs_csi_role_arn" {
  description = "IAM role of the EBS CSI controller."
  value       = aws_iam_role.ebs_csi.arn
}

output "data_key_arn_for_storageclass" {
  description = "KMS key ARN to put in the gp3-encrypted StorageClass (kubernetes/storage/storageclass-ebs.yaml parameter kmsKeyId)."
  value       = local.data_key_arn
}
