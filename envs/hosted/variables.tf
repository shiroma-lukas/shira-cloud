variable "nat_mode" {
  description = <<-EOT
    "instance" (a few dollars a month) while the hosted environment only runs test cells;
    switch to "gateway" (~US$70/month, self-healing, scales) before paying customers.
  EOT
  type        = string
  default     = "instance"
}

variable "cells" {
  description = "One entry per customer, keyed by a short slug (becomes shira-<slug>)."
  type = map(object({
    shira_version             = string
    db_instance_class         = optional(string, "db.t4g.medium")
    db_multi_az               = optional(bool, false)
    fleet_instance_type       = optional(string, "m6i.xlarge")
    fleet_architecture        = optional(string, "x86_64")
    fleet_spot                = optional(bool, false)
    fleet_spot_instance_types = optional(list(string), [])
    fleet_min_size            = optional(number, 1)
    fleet_max_size            = optional(number, 3)
    deletion_protection       = optional(bool, true)
  }))
  default = {}
}
