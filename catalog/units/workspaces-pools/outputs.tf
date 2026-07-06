output "pool_id" {
  value = awscc_workspaces_workspaces_pool.main.pool_id
}

output "pool_arn" {
  value = awscc_workspaces_workspaces_pool.main.pool_arn
}

output "directory_id" {
  value = aws_workspaces_directory.main.id
}
