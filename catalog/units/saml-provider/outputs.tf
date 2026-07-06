# stack 未参照。Entra ID 側の Enterprise Application 設定
# （Role クレーム = 「ロール ARN,プロバイダー ARN」ペア）に必要な値のため公開
output "saml_provider_arn" {
  value = aws_iam_saml_provider.entra_id.arn
}

# stack 未参照。同上（Entra ID の Role クレーム設定に使う）
output "saml_role_arn" {
  value = aws_iam_role.workspaces_saml.arn
}
