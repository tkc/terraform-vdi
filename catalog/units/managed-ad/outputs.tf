output "directory_id" {
  value = aws_directory_service_directory.main.id
}

output "dns_ip_addresses" {
  value = aws_directory_service_directory.main.dns_ip_addresses
}

output "alias" {
  value = aws_directory_service_directory.main.alias
}
