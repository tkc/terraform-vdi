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

variable "ingestion_process" {
  description = "WorkSpaces image ingestion process (license/GPU dependent, e.g. BYOL_REGULAR, BYOL_GRAPHICS_G4DN)"
  type        = string
  default     = "BYOL_REGULAR"
}

variable "bundle_compute_type" {
  description = "Compute type for the auto-created WorkSpaces bundle (e.g. STANDARD, PERFORMANCE, GRAPHICS_G4DN)"
  type        = string
  default     = "STANDARD"
}
