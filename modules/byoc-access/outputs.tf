output "role_arn" {
  description = "Send this to Shira Cloud together with the external id."
  value       = aws_iam_role.operator.arn
}
