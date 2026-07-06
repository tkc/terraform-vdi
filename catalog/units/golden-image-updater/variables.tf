variable "image_builder_pipeline_arn" {
  description = "ARN of the EC2 Image Builder pipeline to trigger"
  type        = string
}

variable "workspaces_pool_id" {
  description = "WorkSpaces Pool ID to update when new image is ready"
  type        = string
}

variable "maintenance_window_id" {
  description = "SSM Maintenance Window ID to filter EventBridge on (prevents firing on unrelated windows)"
  type        = string
}

variable "image_arn_prefix" {
  description = "Image Builder image ARN prefix to filter EventBridge on (prevents pool updates from unrelated pipelines)"
  type        = string
}
