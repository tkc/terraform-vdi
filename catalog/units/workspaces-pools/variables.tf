variable "directory_id" {
  description = "AWS Managed Microsoft AD directory ID"
  type        = string
}

variable "subnet_ids" {
  description = "Subnets (2 AZs) for WorkSpaces session hosts"
  type        = list(string)
}

variable "bundle_id" {
  description = "WorkSpaces bundle ID (Windows version and compute type)"
  type        = string
  # 例: wsb-gk1wpk43z = Standard with Windows Server 2022

  validation {
    condition     = can(regex("^wsb-[0-9a-z]+$", var.bundle_id))
    error_message = "bundle_id は wsb- で始まる WorkSpaces Bundle ID を指定する。"
  }
}

variable "pool_name" {
  description = "WorkSpaces Pool name (also used as the application settings group)"
  type        = string
  default     = "vdi-pool"
}

variable "workspace_access_url" {
  description = "FQDN for WorkSpaces web access (used in SAML relay state)"
  type        = string
}

variable "max_user_sessions" {
  description = "Maximum concurrent user sessions (= provisioned pool capacity)"
  type        = number
  default     = 2

  validation {
    condition     = var.max_user_sessions >= 1
    error_message = "max_user_sessions は 1 以上を指定する。"
  }
}

variable "disconnect_timeout_seconds" {
  description = "Session lifetime after disconnect (recovery grace period)"
  type        = number
  default     = 3600
}

variable "idle_disconnect_timeout_seconds" {
  description = "Idle time before auto-disconnect (frees pool capacity)"
  type        = number
  default     = 1800
}

variable "max_user_duration_seconds" {
  description = "Hard session limit (forces reset within one business day)"
  type        = number
  default     = 28800
}

variable "tags" {
  description = "Tags for awscc-managed resources (awscc does not inherit aws provider default_tags)"
  type        = map(string)
  default = {
    Project     = "vdi"
    ManagedBy   = "terragrunt"
    Environment = "prod"
  }
}
