variable "domain_name" {
  description = "Active Directory domain name (e.g. corp.example.com)"
  type        = string
}

variable "ad_password_secret_arn" {
  description = "ARN of Secrets Manager secret containing the AD admin password"
  type        = string
}

variable "vpc_id" {
  description = "VPC to deploy the directory into"
  type        = string
}

variable "subnet_ids" {
  description = "Two subnet IDs in different AZs for Managed AD"
  type        = list(string)
  validation {
    condition     = length(var.subnet_ids) == 2
    error_message = "Managed AD requires exactly 2 subnets in different AZs."
  }
}
