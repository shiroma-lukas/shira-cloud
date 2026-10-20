variable "name" {
  type    = string
  default = "shira-byoc"
}

variable "region" {
  description = "The customer's region."
  type        = string
  default     = "sa-east-1"
}

variable "cidr" {
  description = "Pick a range that doesn't collide with the customer's networks."
  type        = string
  default     = "10.40.0.0/16"
}

variable "customer_role_arn" {
  type = string
}

variable "external_id" {
  type      = string
  sensitive = true
}

variable "shira_version" {
  type = string
}
