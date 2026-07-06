variable "directory_id" {
  description = "AWS Managed Microsoft AD directory ID"
  type        = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "bundle_id" {
  description = "WorkSpaces bundle ID (Windows version and compute type)"
  type        = string
  # 例: wsb-gk1wpk43z = Standard with Windows Server 2022
}

variable "pool_name" {
  type    = string
  default = "vdi-pool"
}

variable "workspace_access_url" {
  description = "FQDN for WorkSpaces web access (used in SAML relay state)"
  type        = string
}

variable "max_user_sessions" {
  description = "Maximum concurrent user sessions"
  type        = number
  default     = 2
}

variable "desired_user_sessions" {
  description = "Desired running sessions (0 = scale to zero when idle)"
  type        = number
  default     = 0
}
