data "aws_availability_zones" "this" {
  state = "available"
}

locals {
  azs          = slice(data.aws_availability_zones.this.names, 0, var.az_count)
  use_gateway  = var.nat_mode == "gateway"
  nat_gateways = local.use_gateway ? (var.single_nat_gateway ? 1 : var.az_count) : 0
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = var.name }
}

# Strip the default security group of all rules so nothing uses it by accident.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = var.name }
}

# Public subnets hold only NAT gateways. Nothing Shira runs is publicly reachable.
resource "aws_subnet" "public" {
  count             = var.az_count
  vpc_id            = aws_vpc.this.id
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(var.cidr, 8, count.index)
  tags              = { Name = "${var.name}-public-${local.azs[count.index]}" }
}

resource "aws_subnet" "private" {
  count             = var.az_count
  vpc_id            = aws_vpc.this.id
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(var.cidr, 8, 10 + count.index)
  tags              = { Name = "${var.name}-private-${local.azs[count.index]}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = { Name = "${var.name}-public" }
}

resource "aws_route_table_association" "public" {
  count          = var.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  count  = local.use_gateway ? local.nat_gateways : 1
  domain = "vpc"
  tags   = { Name = "${var.name}-nat-${count.index}" }
}

resource "aws_nat_gateway" "this" {
  count         = local.nat_gateways
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = { Name = "${var.name}-${count.index}" }
  depends_on    = [aws_internet_gateway.this]
}

# --- NAT instance (nat_mode = "instance") ----------------------------------------------
# Plain Amazon Linux doing IP forwarding and masquerade: no third-party AMI to trust.
data "aws_ssm_parameter" "al2023_arm64" {
  count = local.use_gateway ? 0 : 1
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

resource "aws_security_group" "nat" {
  count       = local.use_gateway ? 0 : 1
  name        = "${var.name}-nat"
  description = "NAT instance: forwards traffic from the VPC, accepts nothing from outside"
  vpc_id      = aws_vpc.this.id
}

resource "aws_vpc_security_group_ingress_rule" "nat_from_vpc" {
  count             = local.use_gateway ? 0 : 1
  security_group_id = aws_security_group.nat[0].id
  ip_protocol       = "-1"
  cidr_ipv4         = var.cidr
}

resource "aws_vpc_security_group_egress_rule" "nat_out" {
  count             = local.use_gateway ? 0 : 1
  security_group_id = aws_security_group.nat[0].id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_instance" "nat" {
  count                  = local.use_gateway ? 0 : 1
  ami                    = data.aws_ssm_parameter.al2023_arm64[0].insecure_value
  instance_type          = var.nat_instance_type
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.nat[0].id]
  source_dest_check      = false # it forwards traffic that isn't addressed to it

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
  }

  user_data = <<-EOT
    #!/bin/bash
    set -euxo pipefail
    dnf install -y iptables-services
    echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/90-nat.conf
    sysctl --system
    iface=$(ip route show default | awk '{print $5; exit}')
    iptables -F FORWARD
    iptables -t nat -F POSTROUTING
    iptables -t nat -A POSTROUTING -o "$iface" -s ${var.cidr} -j MASQUERADE
    service iptables save
    systemctl enable --now iptables
  EOT

  tags = { Name = "${var.name}-nat" }

  lifecycle {
    ignore_changes = [ami] # a new AMI shouldn't replace the NAT out from under a running cell
  }
}

resource "aws_eip_association" "nat" {
  count         = local.use_gateway ? 0 : 1
  allocation_id = aws_eip.nat[0].id
  instance_id   = aws_instance.nat[0].id
}

# If the NAT instance's underlying host fails, AWS recovers it onto healthy hardware with the
# same instance ID, private IP, and Elastic IP, so routes keep working.
resource "aws_cloudwatch_metric_alarm" "nat_recover" {
  count               = local.use_gateway ? 0 : 1
  alarm_name          = "${var.name}-nat-recover"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_System"
  dimensions          = { InstanceId = aws_instance.nat[0].id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  alarm_actions       = ["arn:aws:automate:${data.aws_region.current.region}:ec2:recover"]
}

resource "aws_route_table" "private" {
  count  = var.az_count
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-private-${local.azs[count.index]}" }
}

resource "aws_route" "private_default" {
  count                  = var.az_count
  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = local.use_gateway ? aws_nat_gateway.this[var.single_nat_gateway ? 0 : count.index].id : null
  network_interface_id   = local.use_gateway ? null : aws_instance.nat[0].primary_network_interface_id
}

resource "aws_route_table_association" "private" {
  count          = var.az_count
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# S3 traffic (config, transcripts) stays on the AWS network and skips NAT charges.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id
  tags              = { Name = "${var.name}-s3" }
}

data "aws_region" "current" {}

# Flow logs: an independent record of every connection, outside the hosts' control.
resource "aws_cloudwatch_log_group" "flow" {
  name              = "/shira/${var.name}/vpc-flow"
  retention_in_days = var.flow_log_retention_days
}

resource "aws_iam_role" "flow" {
  name = "${var.name}-vpc-flow"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "vpc-flow-logs.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy" "flow" {
  role = aws_iam_role.flow.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
      Resource = "${aws_cloudwatch_log_group.flow.arn}:*"
    }]
  })
}

resource "aws_flow_log" "this" {
  vpc_id          = aws_vpc.this.id
  traffic_type    = "ALL"
  log_destination = aws_cloudwatch_log_group.flow.arn
  iam_role_arn    = aws_iam_role.flow.arn
}
