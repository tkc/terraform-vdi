output "vpc_id" {
  value = aws_vpc.main.id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "private_route_table_ids" {
  value = aws_route_table.private[*].id
}

output "sg_workspaces_id" {
  value = aws_security_group.workspaces.id
}

# stack 未参照。Managed AD は AWS 管理の SG を持つため通常は不要だが、
# ディレクトリの SG ルールを手動調整する運用が発生した場合の参照用に公開
output "sg_managed_ad_id" {
  value = aws_security_group.managed_ad.id
}
