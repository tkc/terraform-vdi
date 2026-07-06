output "saml_provider_arn" {
  value = aws_iam_saml_provider.entra_id.arn
}

output "saml_role_arn" {
  value = aws_iam_role.workspaces_saml.arn
}
