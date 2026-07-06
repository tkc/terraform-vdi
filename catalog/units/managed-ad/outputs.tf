output "directory_id" {
  value = aws_directory_service_directory.main.id
}

output "dns_ip_addrs" {
  value = aws_directory_service_directory.main.dns_ip_addrs
}

output "alias" {
  value = aws_directory_service_directory.main.alias
}
