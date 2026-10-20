variable "operator_account_id" {
  description = "Shira Cloud's AWS account, allowed to assume the role."
  type        = string
}

variable "external_id" {
  description = "Shared secret agreed with the customer, preventing confused-deputy use of the role."
  type        = string
  sensitive   = true
}

variable "role_name" {
  type    = string
  default = "shira-cloud-operator"
}

variable "managed_policy_arns" {
  description = "What the operator may do. PowerUserAccess plus the scoped IAM policy below covers deploying a cell."
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/PowerUserAccess"]
}
