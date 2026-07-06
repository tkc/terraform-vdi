output "maintenance_window_id" {
  value = aws_ssm_maintenance_window.golden_image.id
}

output "patch_baseline_id" {
  value = aws_ssm_patch_baseline.windows.id
}
