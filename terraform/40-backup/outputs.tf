output "vault_name" {
  description = "Primary backup vault."
  value       = aws_backup_vault.this.name
}

output "backup_plan_id" {
  description = "Backup plan id (use with aws backup start-backup-job to test on demand)."
  value       = aws_backup_plan.daily.id
}

output "backup_role_arn" {
  description = "Role AWS Backup uses (pass it to start-backup-job / restore jobs)."
  value       = aws_iam_role.backup.arn
}

output "dr_vault_name" {
  description = "DR vault name (empty when cross-region copy is off)."
  value       = var.enable_cross_region_copy ? aws_backup_vault.dr[0].name : ""
}
