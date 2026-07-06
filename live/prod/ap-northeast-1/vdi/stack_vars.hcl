locals {
  region      = "ap-northeast-1"
  environment = "prod"

  # ── ネットワーク ──────────────────────────────────────
  vpc_cidr            = "10.10.0.0/16"
  other_account_cidrs = ["10.20.0.0/16"]  # 接続先 AWS アカウントの CIDR

  # ── Transit Gateway ────────────────────────────────────
  # 他アカウントが所有し RAM 共有された TGW の ID
  transit_gateway_id = "tgw-XXXXXXXXXXXXXXXXX"  # 要確認

  # ── Active Directory ────────────────────────────────────
  ad_domain_name         = "corp.example.com"
  ad_password_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:ACCOUNT_ID:secret:vdi/ad-admin-password"

  # ── WorkSpaces Pools ────────────────────────────────────
  workspaces_bundle_id  = "wsb-gk1wpk43z"  # 要確認: コンソールで使用可能な Bundle ID
  pool_name             = "vdi-pool-prod"
  workspace_access_url  = "workspaces.example.com"
  max_user_sessions     = 2
  desired_user_sessions = 0  # 未使用時はゼロ（コスト最適化）
}
