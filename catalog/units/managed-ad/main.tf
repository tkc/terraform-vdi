# ══════════════════════════════════════════════════════════════════
# unit: managed-ad — WorkSpaces のドメイン参加基盤
#
# 役割の分担に注意:
#   - 人の認証     = Entra ID（saml-provider ユニット）が担う
#   - マシン認証   = この Managed AD が担う（ドメイン参加・GPO・Office 連携）
# ユーザー同期は既存の Entra ID Connect ハイブリッド構成に依存する。
#
# AD Connector でなく Managed AD を選んだ理由:
# オンプレ AD への依存を持たず、AWS 内で完結させるため。
# ══════════════════════════════════════════════════════════════════

# 管理者パスワードは Secrets Manager 参照のみ（コードに値を書かない）
data "aws_secretsmanager_secret_version" "ad_password" {
  secret_id = var.ad_password_secret_arn
}

resource "aws_directory_service_directory" "main" {
  name     = var.domain_name
  password = data.aws_secretsmanager_secret_version.ad_password.secret_string
  edition  = "Standard"
  type     = "MicrosoftAD"

  vpc_settings {
    vpc_id     = var.vpc_id
    subnet_ids = var.subnet_ids
  }
}
