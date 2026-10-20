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
  description = "Primary instance type. Must match architecture."
  type        = string
}

variable "architecture" {
  description = "\"x86_64\" or \"arm64\" (Graviton, ~20% cheaper per vCPU). gVisor and the worker image support both."
  type        = string
  default     = "x86_64"
  validation {
    condition     = contains(["x86_64", "arm64"], var.architecture)
    error_message = "architecture must be \"x86_64\" or \"arm64\"."
  }
}

variable "spot" {
  description = <<-EOT
    Run hosts on Spot (typically 60-70% cheaper). Safe for Shira: a reclaimed host's task
    loses its lease and is retried on another host. Each extra type in spot_instance_types
    widens the capacity pool, which makes interruptions rarer.
  EOT
  type        = bool
  default     = false
}

variable "spot_instance_types" {
  description = "With spot: alternative instance types besides instance_type, same architecture."
  type        = list(string)
  default     = []
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
