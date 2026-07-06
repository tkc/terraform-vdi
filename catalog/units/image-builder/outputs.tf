output "pipeline_arn" {
  value = aws_imagebuilder_image_pipeline.vdi.arn
}

output "pipeline_name" {
  value = aws_imagebuilder_image_pipeline.vdi.name
}
