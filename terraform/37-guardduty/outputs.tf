output "detector_id" {
  description = "GuardDuty detector id (empty when disabled)."
  value       = var.enable_guardduty ? aws_guardduty_detector.this[0].id : ""
}
