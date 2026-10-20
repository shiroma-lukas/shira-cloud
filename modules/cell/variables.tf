variable "name" {
  description = "Cell name, unique per account and region (e.g. shira-acme). Prefixes every resource."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.name))
    error_message = "Use 3-31 lowercase letters, digits, and hyphens, starting with a letter."
  }
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  description = "Subnets for the database and the sandbox fleet. At least two AZs."
  type        = list(string)
}

variable "shira_version" {
  description = "Git ref of the open-source shira repo the fleet runs (tag or commit)."
  type        = string
}

variable "shira_repo_url" {
  type    = string
  default = "https://github.com/shiroma-lukas/shira.git"
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.medium"
}

variable "db_multi_az" {
  description = "Standby in a second AZ. Recommended for paying customers."
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Protect the database and keep a final snapshot. Turn off only for throwaway cells."
  type        = bool
  default     = true
}

variable "fleet_instance_type" {
  type    = string
  default = "m6i.xlarge"
}

variable "fleet_min_size" {
  type    = number
  default = 1
}

variable "fleet_max_size" {
  type    = number
  default = 3
}

variable "max_task_minutes" {
  description = "Longest a task may run. Hosts wait this long for the current task when stopping."
  type        = number
  default     = 60
}

variable "transcript_retention_days" {
  description = "Transcripts are deleted after this many days (PRD FR-L3 default: 90)."
  type        = number
  default     = 90
}

variable "log_retention_days" {
  type    = number
  default = 30
}
