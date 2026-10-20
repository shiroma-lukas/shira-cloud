variable "name" {
  description = "Prefix for resource names."
  type        = string
}

variable "cidr" {
  description = "VPC CIDR. Subnets are /24s carved from it."
  type        = string
  default     = "10.40.0.0/16"
}

variable "az_count" {
  description = "Availability zones to span (sa-east-1 has three)."
  type        = number
  default     = 2
}

variable "single_nat_gateway" {
  description = "With nat_mode = gateway: one NAT gateway for all AZs (cheaper) instead of one per AZ (survives an AZ outage)."
  type        = bool
  default     = true
}

variable "nat_mode" {
  description = <<-EOT
    How private subnets reach the internet:
    "gateway"  - managed NAT gateway: scales and heals itself, ~US$70/month fixed in sa-east-1.
    "instance" - one small arm64 instance doing NAT: a few dollars a month, fine for test cells
                 and low traffic; a single point of failure until AWS auto-recovers it.
  EOT
  type        = string
  default     = "gateway"
  validation {
    condition     = contains(["gateway", "instance"], var.nat_mode)
    error_message = "nat_mode must be \"gateway\" or \"instance\"."
  }
}

variable "nat_instance_type" {
  description = "With nat_mode = instance. Must be arm64 (Graviton)."
  type        = string
  default     = "t4g.nano"
}

variable "flow_log_retention_days" {
  description = "Retention for VPC flow logs, which record every connection the fleet makes."
  type        = number
  default     = 30
}
