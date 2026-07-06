# stack 未参照（orchestrator 廃止で TF 内の参照は消えた）。
# runbook の手動パイプライン実行（aws imagebuilder start-image-pipeline-execution）
# で使う運用値のため公開を維持
output "pipeline_arn" {
  value = aws_imagebuilder_image_pipeline.vdi.arn
}

# stack 未参照。同上（運用 CLI・コンソール確認用）
output "pipeline_name" {
  value = aws_imagebuilder_image_pipeline.vdi.name
}

# このパイプラインが生成するイメージの ARN プレフィックス。
# EventBridge のフィルタに使う（形式: .../image/<レシピ名>/）
output "image_arn_prefix" {
  value = "arn:aws:imagebuilder:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:image/${aws_imagebuilder_image_recipe.vdi.name}/"
}
