variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.10.0.0/16"
}

variable "other_account_cidrs" {
  description = "CIDR ranges of other AWS accounts connected via Transit Gateway"
  type        = list(string)
  default     = []
}

variable "other_account_ports" {
  description = "TCP ports allowed to other AWS accounts via TGW (least privilege)"
  type        = list(number)
  default     = [443]
}
