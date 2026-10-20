output "app_secret_arn" {
  description = "Set its value out of band; see docs/operations.md."
  value       = aws_secretsmanager_secret.app.arn
}

output "config_bucket" {
  value = aws_s3_bucket.config.bucket
}

output "transcripts_bucket" {
  value = aws_s3_bucket.transcripts.bucket
}

output "db_address" {
  value = aws_db_instance.this.address
}

output "db_secret_arn" {
  value = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "fleet_asg_name" {
  value = module.fleet.asg_name
}
