output "vpc_id" {
  value = aws_vpc.this.id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "nat_public_ips" {
  description = "Fleet egress addresses, for customers who allowlist inbound traffic (e.g. GitHub Enterprise IP allowlists)."
  value       = aws_eip.nat[*].public_ip
}
