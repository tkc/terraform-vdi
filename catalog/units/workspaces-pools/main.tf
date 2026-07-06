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
    enable_internet_access              = false  # 閉鎖網のためインターネット不可
    enable_maintenance_mode             = true
    user_enabled_as_local_administrator = false
  }

  # Entra ID (SAML) を IdP として登録
  saml_properties {
    relay_state_parameter_name = "RelayState"
    status                     = "ENABLED"
    user_access_url            = "https://${var.workspace_access_url}"
  }
}

resource "aws_workspaces_pool" "main" {
  name         = var.pool_name
  bundle_id    = data.aws_workspaces_bundle.windows.id
  directory_id = aws_workspaces_directory.main.id
  description  = "社内 VDI Pool — 最大同時 ${var.max_user_sessions} セッション"

  capacity {
    desired_user_sessions = var.desired_user_sessions
    max_user_sessions     = var.max_user_sessions
    min_user_sessions     = 0
  }

  application_settings {
    enabled        = true
    settings_group = var.pool_name
  }

  storage_connectors {
    connector_type = "HOMEFOLDERS"
  }

  lifecycle {
    # Golden Image の自動更新で bundle_id が変わるため ignore
    ignore_changes = [bundle_id]
  }
}

resource "aws_workspaces_pool_session" "main" {
  pool_id = aws_workspaces_pool.main.id

  # セッションタイムアウト設定
  disconnect_timeout_in_seconds      = 3600   # 切断後 1 時間でセッション終了
  idle_disconnect_timeout_in_seconds = 1800   # アイドル 30 分で切断
  max_user_duration_in_seconds       = 28800  # 最大 8 時間
}
