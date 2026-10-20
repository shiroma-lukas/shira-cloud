output "security_group_id" {
  value = aws_security_group.fleet.id
}

output "asg_name" {
  value = aws_autoscaling_group.fleet.name
}

output "role_arn" {
  value = aws_iam_role.fleet.arn
}
