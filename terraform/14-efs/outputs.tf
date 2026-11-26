output "efs_file_system_id" {
  description = "EFS file system id (used by kubernetes/storage/storageclass-efs.yaml)."
  value       = aws_efs_file_system.shared.id
}

output "efs_access_point_id" {
  description = "EFS access point id (static PV example in kubernetes/storage)."
  value       = aws_efs_access_point.shared.id
}

output "efs_file_system_arn" {
  description = "EFS ARN (AWS Backup selection)."
  value       = aws_efs_file_system.shared.arn
}
