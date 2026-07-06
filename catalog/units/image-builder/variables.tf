variable "subnet_id" {
  description = "Private subnet ID for Image Builder EC2 instances"
  type        = string
}

variable "security_group_id" {
  description = "Security group for Image Builder instances"
  type        = string
}
