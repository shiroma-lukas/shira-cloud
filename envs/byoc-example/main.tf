# A cell in a customer's own AWS account (BYOC). Same modules as hosted; the code never
# leaves the customer's account. Shira Cloud applies this with the customer's operator
# role (modules/byoc-access), which the customer created and can revoke.
terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
  backend "s3" {
    key          = "byoc/example/terraform.tfstate"
    region       = "sa-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region
  assume_role {
    role_arn    = var.customer_role_arn
    external_id = var.external_id
  }
  default_tags {
    tags = { "shira:managed-by" = "shira-cloud", "shira:env" = "byoc" }
  }
}

module "network" {
  source = "../../modules/network"
  name   = var.name
  cidr   = var.cidr
}

module "cell" {
  source             = "../../modules/cell"
  name               = var.name
  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids
  shira_version      = var.shira_version
  db_multi_az        = true
}

output "app_secret_arn" {
  value = module.cell.app_secret_arn
}

output "config_bucket" {
  value = module.cell.config_bucket
}

output "egress_ips" {
  value = module.network.nat_public_ips
}
