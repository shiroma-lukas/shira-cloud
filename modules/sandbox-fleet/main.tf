data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

locals {
  # Named here, not read from the group: the launch template (inside the group) needs it.
  asg_name       = "${var.name}-fleet"
  drain_hook     = "drain"
  ubuntu_arch    = var.architecture == "arm64" ? "arm64" : "amd64"
  instance_types = distinct(concat([var.instance_type], var.spot ? var.spot_instance_types : []))
}

# Ubuntu 24.04 LTS, resolved at plan time. gVisor publishes Debian/Ubuntu packages.
data "aws_ssm_parameter" "ubuntu" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/${local.ubuntu_arch}/hvm/ebs-gp3/ami-id"
}

# Catch an x86 type in an arm64 fleet (or the reverse) at plan time, not at boot.
data "aws_ec2_instance_type" "fleet" {
  for_each      = toset(local.instance_types)
  instance_type = each.value
}

# No inbound rules at all: hosts are reached through SSM, never SSH.
resource "aws_security_group" "fleet" {
  name        = "${var.name}-fleet"
  description = "Sandbox hosts for cell ${var.name}: outbound only"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.fleet.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_iam_role" "fleet" {
  name = "${var.name}-fleet"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
  ])
  role       = aws_iam_role.fleet.name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "fleet" {
  role = aws_iam_role.fleet.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadCellSecrets"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = [var.app_secret_arn, var.db_secret_arn, var.db_app_secret_arn]
      },
      {
        Sid      = "ListConfig"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "arn:aws:s3:::${var.config_bucket}"
      },
      {
        Sid      = "ReadConfig"
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "arn:aws:s3:::${var.config_bucket}/*"
      },
      {
        Sid      = "DrainOnScaleIn"
        Effect   = "Allow"
        Action   = ["autoscaling:CompleteLifecycleAction", "autoscaling:RecordLifecycleActionHeartbeat"]
        Resource = "arn:aws:autoscaling:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:autoScalingGroup:*:autoScalingGroupName/${local.asg_name}"
      },
      {
        # The dispatcher writes each run's transcript once and never reads it back.
        Sid      = "WriteTranscripts"
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = "arn:aws:s3:::${var.transcripts_bucket}/transcripts/*"
      },
    ]
  })
}

resource "aws_iam_instance_profile" "fleet" {
  name = "${var.name}-fleet"
  role = aws_iam_role.fleet.name
}

resource "aws_launch_template" "fleet" {
  lifecycle {
    precondition {
      condition = alltrue([
        for t in data.aws_ec2_instance_type.fleet : contains(t.supported_architectures, var.architecture)
      ])
      error_message = "Every fleet instance type must support architecture ${var.architecture}."
    }
  }

  name_prefix   = "${var.name}-fleet-"
  image_id      = data.aws_ssm_parameter.ubuntu.insecure_value
  instance_type = var.instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.fleet.arn
  }

  vpc_security_group_ids = [aws_security_group.fleet.id]

  # IMDSv2 only, with a hop limit of 1: processes in containers are one hop further
  # away and can't fetch the host's credentials. The egress proxy also refuses
  # link-local addresses, so this is defense in depth.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size           = var.root_volume_gb
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  monitoring {
    enabled = true
  }

  user_data = base64encode(templatefile("${path.module}/bootstrap.sh.tftpl", {
    region              = data.aws_region.current.region
    shira_repo_url      = var.shira_repo_url
    shira_version       = var.shira_version
    app_secret_arn      = var.app_secret_arn
    db_secret_arn       = var.db_secret_arn
    db_app_secret_arn   = var.db_app_secret_arn
    db_address          = var.db_address
    db_port             = var.db_port
    config_bucket       = var.config_bucket
    transcripts_bucket  = var.transcripts_bucket
    log_group_dispatch  = var.log_groups["dispatcher"]
    log_group_egress    = var.log_groups["egress"]
    log_group_bootstrap = var.log_groups["bootstrap"]
    stop_timeout_sec    = var.max_task_minutes * 60 + 300
    asg_name            = local.asg_name
    drain_hook          = local.drain_hook
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.name}-fleet", "shira:cell" = var.name }
  }

  tag_specifications {
    resource_type = "volume"
    tags          = { Name = "${var.name}-fleet", "shira:cell" = var.name }
  }
}

resource "aws_autoscaling_group" "fleet" {
  name                = local.asg_name
  vpc_zone_identifier = var.subnet_ids
  min_size            = var.min_size
  max_size            = var.max_size
  health_check_type   = "EC2"
  # With Spot, replace a host as soon as AWS signals elevated interruption risk.
  capacity_rebalance = var.spot

  dynamic "launch_template" {
    for_each = var.spot ? [] : [1]
    content {
      id      = aws_launch_template.fleet.id
      version = aws_launch_template.fleet.latest_version
    }
  }

  dynamic "mixed_instances_policy" {
    for_each = var.spot ? [1] : []
    content {
      instances_distribution {
        on_demand_base_capacity                  = 0
        on_demand_percentage_above_base_capacity = 0
        spot_allocation_strategy                 = "price-capacity-optimized"
      }
      launch_template {
        launch_template_specification {
          launch_template_id = aws_launch_template.fleet.id
          version            = aws_launch_template.fleet.latest_version
        }
        dynamic "override" {
          for_each = local.instance_types
          content {
            instance_type = override.value
          }
        }
      }
    }
  }

  # Scale-in, instance refresh, and Spot rebalancing hold a leaving host in Terminating:Wait.
  # The host sees it in instance metadata, stops its dispatcher (SIGTERM: the current task
  # finishes), and completes the action itself (shira-drain in the bootstrap script). It
  # sends heartbeats while it waits, so a host that dies mid-drain is released after
  # heartbeat_timeout. A Spot interruption itself gives two minutes and can't wait: that
  # task is retried elsewhere.
  initial_lifecycle_hook {
    name                 = local.drain_hook
    lifecycle_transition = "autoscaling:EC2_INSTANCE_TERMINATING"
    heartbeat_timeout    = 900
    default_result       = "CONTINUE"
  }

  # Rolling replacement when the launch template changes (new shira_version, AMI, size).
  # Replaced hosts drain through the lifecycle hook above, so an upgrade waits for running
  # tasks instead of retrying them.
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "shira:cell"
    value               = var.name
    propagate_at_launch = true
  }
}
