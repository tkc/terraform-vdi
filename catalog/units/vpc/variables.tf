variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.10.0.0/16"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "other_account_cidrs" {
  description = "CIDR ranges of other AWS accounts connected via Transit Gateway"
  type        = list(string)
  default     = []
}
