variable "image_builder_pipeline_arn" {
  description = "ARN of the EC2 Image Builder pipeline to trigger"
  type        = string
}

variable "workspaces_pool_id" {
  description = "WorkSpaces Pool ID to update when new image is ready"
  type        = string
}
