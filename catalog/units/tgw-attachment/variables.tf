variable "transit_gateway_id" {
  description = "ID of the Transit Gateway (owned by another account, shared via RAM)"
  type        = string

  validation {
    condition     = can(regex("^tgw-[0-9a-f]{17}$", var.transit_gateway_id))
    error_message = "transit_gateway_id は tgw-xxxxxxxxxxxxxxxxx 形式で指定する（stack_vars.hcl のプレースホルダーを実値に更新すること）。"
  }
}

variable "vpc_id" {
  description = "VPC ID to attach to the Transit Gateway"
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs used for the TGW attachment ENIs (one per AZ)"
  type        = list(string)
}

variable "route_table_ids" {
  description = "Private route table IDs to add routes to other accounts"
  type        = list(string)
}

variable "other_account_cidrs" {
  description = "CIDR ranges of other AWS accounts accessible via TGW"
  type        = list(string)
}
