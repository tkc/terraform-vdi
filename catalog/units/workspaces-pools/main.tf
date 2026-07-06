# ══════════════════════════════════════════════════════════════════
# unit: workspaces-pools — VDI 本体（セッションベースのデスクトップ）
#
# Personal でなく Pools を採用: ユーザー固定のデスクトップではなく、
# 接続時にセッションを割り当てる方式。容量 = 同時接続上限（2）。
#
# provider の使い分け:
#   - ディレクトリ登録 = AWS provider（aws_workspaces_directory）
#   - Pool 本体        = AWSCC provider（AWS provider が Pools 未対応のため）
# ══════════════════════════════════════════════════════════════════

data "aws_workspaces_bundle" "windows" {
  bundle_id = var.bundle_id
}

resource "aws_workspaces_directory" "main" {
  directory_id = var.directory_id
  subnet_ids   = var.subnet_ids

  workspace_access_properties {
    device_type_android    = "DENY"
    device_type_chromeos   = "DENY"
    device_type_ios        = "DENY"
    device_type_linux      = "DENY"
    device_type_osx        = "ALLOW"
    device_type_web        = "ALLOW"
    device_type_windows    = "ALLOW"
    device_type_zeroclient = "DENY"
  }

  workspace_creation_properties {
    enable_internet_access              = false # 閉鎖網のためインターネット不可
    enable_maintenance_mode             = true
    user_enabled_as_local_administrator = false
    # ここに配線しないと SG は定義だけで一度も効かない（review-log #12-2）。
    # AD ポートセット（vpc の ad_ports）はこの SG 経由で適用される
    custom_security_group_id = var.security_group_id
  }

  # Entra ID (SAML) を IdP として登録
  saml_properties {
    relay_state_parameter_name = "RelayState"
    status                     = "ENABLED"
    user_access_url            = "https://${var.workspace_access_url}"
  }
}

# WorkSpaces Pools は AWS provider 未対応のため AWSCC (Cloud Control) provider を使用
resource "awscc_workspaces_workspaces_pool" "main" {
  pool_name    = var.pool_name
  bundle_id    = data.aws_workspaces_bundle.windows.id
  directory_id = aws_workspaces_directory.main.id
  description  = "VDI Pool — 最大同時 ${var.max_user_sessions} セッション"

  capacity = {
    desired_user_sessions = var.max_user_sessions # 同時最大セッション数 = 確保容量
  }

  application_settings = {
    status         = "ENABLED" # アプリ設定の永続化
    settings_group = var.pool_name
  }

  # タイムアウト値と根拠は docs/architecture.md「セッションポリシー」表が単一情報源
  timeout_settings = {
    disconnect_timeout_in_seconds      = var.disconnect_timeout_seconds
    idle_disconnect_timeout_in_seconds = var.idle_disconnect_timeout_seconds
    max_user_duration_in_seconds       = var.max_user_duration_seconds
  }

  # awscc provider は aws provider の default_tags を継承しないため明示付与
  # （付けないとコスト配賦・棚卸しから漏れる）
  tags = [for k, v in var.tags : { key = k, value = v }]

  lifecycle {
    # Golden Image の自動更新で bundle_id が変わるため ignore
    ignore_changes = [bundle_id]
  }
}
