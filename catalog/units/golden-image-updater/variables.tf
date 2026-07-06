variable "workspaces_pool_id" {
  description = "WorkSpaces Pool ID to update when new image is ready"
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

variable "bundle_user_storage_gb" {
  description = "User volume size (GB) for the auto-created bundle (must be valid for the compute type)"
  type        = number
  default     = 50
}

variable "bundle_root_storage_gb" {
  description = "Root volume size (GB) for the auto-created bundle (must be valid for the compute type)"
  type        = number
  default     = 80
}
