data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  # Bucket names are global; the account id keeps them unique.
  bucket_prefix = "${var.name}-${data.aws_caller_identity.current.account_id}"
}

# --- Secrets -------------------------------------------------------------------------
# Created empty. Values are set out of band (see docs/operations.md) so they never enter
# Terraform state: {"github_app_id": "...", "github_private_key": "...", "anthropic_api_key": "..."}
resource "aws_secretsmanager_secret" "app" {
  name                    = "shira/${var.name}/app"
  description             = "GitHub App credentials and Anthropic API key for cell ${var.name}"
  recovery_window_in_days = var.deletion_protection ? 30 : 0
}

# --- Database --------------------------------------------------------------------------
resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.private_subnet_ids
}

resource "aws_security_group" "db" {
  name        = "${var.name}-db"
  description = "Postgres for cell ${var.name}: reachable from the cell's fleet only"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "db_from_fleet" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = module.fleet.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_db_instance" "this" {
  identifier     = var.name
  engine         = "postgres"
  engine_version = "17"
  instance_class = var.db_instance_class

  allocated_storage     = 20
  max_allocated_storage = 200
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = "shira"
  username = "shira"
  # RDS generates the password and keeps it in Secrets Manager; it never touches state.
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az               = var.db_multi_az

  backup_retention_period    = 7
  copy_tags_to_snapshot      = true
  auto_minor_version_upgrade = true
  deletion_protection        = var.deletion_protection
  skip_final_snapshot        = !var.deletion_protection
  final_snapshot_identifier  = var.deletion_protection ? "${var.name}-final" : null
}

# --- Buckets ---------------------------------------------------------------------------
# config: agent and repo definitions plus the context repo, synced to the fleet.
# transcripts: redacted run transcripts, expired by lifecycle rule.
resource "aws_s3_bucket" "config" {
  bucket        = "${local.bucket_prefix}-config"
  force_destroy = !var.deletion_protection
}

resource "aws_s3_bucket_versioning" "config" {
  bucket = aws_s3_bucket.config.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket" "transcripts" {
  bucket        = "${local.bucket_prefix}-transcripts"
  force_destroy = !var.deletion_protection
}

resource "aws_s3_bucket_lifecycle_configuration" "transcripts" {
  bucket = aws_s3_bucket.transcripts.id
  rule {
    id     = "expire-transcripts"
    status = "Enabled"
    filter {}
    expiration {
      days = var.transcript_retention_days
    }
  }
}

locals {
  buckets = { config = aws_s3_bucket.config, transcripts = aws_s3_bucket.transcripts }
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each                = local.buckets
  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "this" {
  for_each = local.buckets
  bucket   = each.value.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = local.buckets
  bucket   = each.value.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "tls_only" {
  for_each = local.buckets
  bucket   = each.value.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [each.value.arn, "${each.value.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.this]
}

# --- Logs ------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "this" {
  for_each          = toset(["dispatcher", "egress", "bootstrap"])
  name              = "/shira/${var.name}/${each.key}"
  retention_in_days = var.log_retention_days
}

# Count egress denials: a spike means an agent is trying to reach places it shouldn't.
resource "aws_cloudwatch_log_metric_filter" "egress_denied" {
  name           = "${var.name}-egress-denied"
  log_group_name = aws_cloudwatch_log_group.this["egress"].name
  pattern        = "{ $.event = \"egress_denied\" }"
  metric_transformation {
    name      = "EgressDenied"
    namespace = "Shira/${var.name}"
    value     = "1"
  }
}

# --- Fleet -----------------------------------------------------------------------------
module "fleet" {
  source = "../sandbox-fleet"

  name                = var.name
  vpc_id              = var.vpc_id
  subnet_ids          = var.private_subnet_ids
  instance_type       = var.fleet_instance_type
  architecture        = var.fleet_architecture
  spot                = var.fleet_spot
  spot_instance_types = var.fleet_spot_instance_types
  min_size            = var.fleet_min_size
  max_size            = var.fleet_max_size
  max_task_minutes    = var.max_task_minutes
  shira_repo_url      = var.shira_repo_url
  shira_version       = var.shira_version
  app_secret_arn      = aws_secretsmanager_secret.app.arn
  db_secret_arn       = aws_db_instance.this.master_user_secret[0].secret_arn
  db_address          = aws_db_instance.this.address
  db_port             = aws_db_instance.this.port
  config_bucket       = aws_s3_bucket.config.bucket
  transcripts_bucket  = aws_s3_bucket.transcripts.bucket
  log_groups          = { for k, g in aws_cloudwatch_log_group.this : k => g.name }
}
