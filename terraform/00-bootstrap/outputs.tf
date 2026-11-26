output "state_bucket" {
  description = "Bucket that stores all remote state. scripts/env.sh computes the same name."
  value       = aws_s3_bucket.state.id
}

output "state_key_pattern" {
  description = "Where each folder's state lives."
  value       = "s3://${aws_s3_bucket.state.id}/<environment>/<NN-folder>/terraform.tfstate"
}
