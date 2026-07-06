output "directory_id" {
  value = aws_directory_service_directory.main.id
}

# stack 未参照。オンプレ/他ネットワークから AD を名前解決する際の
# DNS フォワーダ設定（条件付きフォワーダの宛先）に使う値のため公開
output "dns_ip_addresses" {
  value = aws_directory_service_directory.main.dns_ip_addresses
}

# stack 未参照。ディレクトリのエイリアス（コンソール確認・トラブルシュート用）
output "alias" {
  value = aws_directory_service_directory.main.alias
}
