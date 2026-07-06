variable "transit_gateway_id" {
  description = "ID of the Transit Gateway (owned by another account, shared via RAM)"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "route_table_ids" {
  description = "Private route table IDs to add routes to other accounts"
  type        = list(string)
}

variable "other_account_cidrs" {
  description = "CIDR ranges of other AWS accounts accessible via TGW"
  type        = list(string)
}
