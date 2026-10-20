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
  description = "One NAT gateway for all AZs (cheaper) instead of one per AZ (survives an AZ outage)."
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "Retention for VPC flow logs, which record every connection the fleet makes."
  type        = number
  default     = 30
}
