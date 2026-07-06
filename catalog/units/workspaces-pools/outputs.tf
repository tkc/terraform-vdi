output "pool_id" {
  value = awscc_workspaces_workspaces_pool.main.pool_id
}

# stack 未参照。IAM ポリシーの Resource 絞り込みや監査での参照用に公開
output "pool_arn" {
  value = awscc_workspaces_workspaces_pool.main.pool_arn
}

output "directory_id" {
  value = aws_workspaces_directory.main.id
}
