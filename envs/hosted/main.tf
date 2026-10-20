# Shira Cloud's hosted environment in sa-east-1: one shared VPC, one cell per customer.
# Cells share the network and nothing else: each has its own database, fleet, buckets,
# secrets, and IAM role.
terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
  # bucket comes from backend.hcl: terraform init -backend-config=backend.hcl
  backend "s3" {
    key          = "hosted/terraform.tfstate"
    region       = "sa-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "sa-east-1"
  default_tags {
    tags = { "shira:managed-by" = "terraform", "shira:env" = "hosted" }
  }
}

module "network" {
  source   = "../../modules/network"
  name     = "shira-hosted"
  az_count = 3
}

module "cell" {
  for_each = var.cells
  source   = "../../modules/cell"

  name               = "shira-${each.key}"
  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids
  shira_version      = each.value.shira_version
  db_instance_class  = each.value.db_instance_class
  db_multi_az        = each.value.db_multi_az
  fleet_min_size     = each.value.fleet_min_size
  fleet_max_size     = each.value.fleet_max_size
}
