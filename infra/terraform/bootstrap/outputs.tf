output "state_bucket_name" {
  description = "Copy this into infra/terraform/backend.tf as the 'bucket' value"
  value       = aws_s3_bucket.tf_state.bucket
}

output "lock_table_name" {
  description = "Copy this into infra/terraform/backend.tf as the 'dynamodb_table' value"
  value       = aws_dynamodb_table.tf_lock.name
}
