resource "aws_iam_saml_provider" "entra_id" {
  name                   = "EntraID-WorkSpaces"
  saml_metadata_document = file("${path.module}/entra-id-metadata.xml")
}

# WorkSpaces Pools が Entra ID ユーザーを引き受けるための IAM ロール
resource "aws_iam_role" "workspaces_saml" {
  name = "WorkSpaces-SAML-Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_saml_provider.entra_id.arn
        }
        Action = "sts:AssumeRoleWithSAML"
        Condition = {
          StringEquals = {
            "SAML:aud" = "https://signin.aws.amazon.com/saml"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "workspaces_saml" {
  name = "WorkSpaces-SAML-Policy"
  role = aws_iam_role.workspaces_saml.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["workspaces:*"]
        Resource = "*"
      }
    ]
  })
}
