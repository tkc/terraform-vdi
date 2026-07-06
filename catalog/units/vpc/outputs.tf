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

output "sg_image_builder_id" {
  value = aws_security_group.image_builder.id
}
