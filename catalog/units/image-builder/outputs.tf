output "pipeline_arn" {
  value = aws_imagebuilder_image_pipeline.vdi.arn
}

output "pipeline_name" {
  value = aws_imagebuilder_image_pipeline.vdi.name
}

# このパイプラインが生成するイメージの ARN プレフィックス。
# EventBridge のフィルタに使う（形式: .../image/<レシピ名>/）
output "image_arn_prefix" {
  value = "arn:aws:imagebuilder:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:image/${aws_imagebuilder_image_recipe.vdi.name}/"
}
