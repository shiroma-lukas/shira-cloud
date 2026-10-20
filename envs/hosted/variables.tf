variable "cells" {
  description = "One entry per customer, keyed by a short slug (becomes shira-<slug>)."
  type = map(object({
    shira_version       = string
    db_instance_class   = optional(string, "db.t4g.medium")
    db_multi_az         = optional(bool, false)
    fleet_instance_type = optional(string, "m6i.xlarge")
    fleet_min_size      = optional(number, 1)
    fleet_max_size      = optional(number, 3)
    deletion_protection = optional(bool, true)
  }))
  default = {}
}
