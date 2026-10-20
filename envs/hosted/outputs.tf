output "cells" {
  value = {
    for k, c in module.cell : k => {
      app_secret_arn = c.app_secret_arn
      config_bucket  = c.config_bucket
      fleet_asg_name = c.fleet_asg_name
    }
  }
}

output "egress_ips" {
  value = module.network.nat_public_ips
}
