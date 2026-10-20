variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "instance_type" {
  type = string
}

variable "min_size" {
  type = number
}

variable "max_size" {
  type = number
}

variable "max_task_minutes" {
  type = number
}

variable "root_volume_gb" {
  description = "Holds images, sandboxes' writable layers, and transcripts awaiting upload."
  type        = number
  default     = 100
}

variable "shira_repo_url" {
  type = string
}

variable "shira_version" {
  type = string
}

variable "app_secret_arn" {
  type = string
}

variable "db_secret_arn" {
  type = string
}

variable "db_address" {
  type = string
}

variable "db_port" {
  type = number
}

variable "config_bucket" {
  type = string
}

variable "transcripts_bucket" {
  type = string
}

variable "log_groups" {
  description = "Log group names keyed by dispatcher, egress, bootstrap."
  type        = map(string)
}
