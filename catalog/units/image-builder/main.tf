# ══════════════════════════════════════════════════════════════════
# unit: image-builder — Golden Image のビルドライン
#
# Windows Server 2022 ベース + 業務アプリ + Windows Update を焼き込んだ
# AMI を作る。パイプラインは週次のネイティブスケジュールで自走し
# （update-windows コンポーネントが最新パッチを適用）、完成イベントを
# golden-image-updater が拾って Pool に反映する。
# ビルドはプライベートサブネット内（インターネット不要）。
# ══════════════════════════════════════════════════════════════════

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# ベースイメージ: Windows Server 2022 Full
data "aws_ami" "windows_base" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }
}

resource "aws_imagebuilder_component" "app_install" {
  name        = "vdi-app-install"
  description = "業務アプリケーションのインストールと設定"
  platform    = "Windows"
  version     = "1.0.0"

  data = yamlencode({
    schemaVersion = "1.0"
    phases = [
      {
        name = "build"
        steps = [
          {
            name   = "InstallApps"
            action = "ExecutePowerShell"
            inputs = {
              commands = [
                # 業務アプリのインストールスクリプトをここに追加
                "Write-Host 'Installing applications...'",
                # 例: S3 からインストーラーを取得（VPC エンドポイント経由）
                # "Read-S3Object -BucketName company-software -Key installer.exe -File C:\\installer.exe",
                "Write-Host 'Application installation complete.'"
              ]
            }
          },
          {
            name   = "ConfigureWindowsSettings"
            action = "ExecutePowerShell"
            inputs = {
              commands = [
                "Set-TimeZone -Id 'Tokyo Standard Time'",
                "Set-WinSystemLocale ja-JP",
              ]
            }
          }
        ]
      },
      {
        name = "validate"
        steps = [
          {
            name   = "ValidateInstall"
            action = "ExecutePowerShell"
            inputs = {
              commands = ["Write-Host 'Validation complete.'"]
            }
          }
        ]
      }
    ]
  })
}

resource "aws_imagebuilder_image_recipe" "vdi" {
  name        = "vdi-golden-image"
  description = "WorkSpaces Pools 用 Windows VDI Golden Image"
  # 注意: レシピは immutable。コンポーネントや parent_image を変更したら
  # この version を必ず上げること（上げないと apply が失敗する）
  parent_image = data.aws_ami.windows_base.id
  version      = "1.0.0"

  component {
    component_arn = aws_imagebuilder_component.app_install.arn
  }

  # Windows Update コンポーネント（AWS 提供）
  component {
    component_arn = "arn:aws:imagebuilder:${data.aws_region.current.region}:aws:component/update-windows/x.x.x"
  }
}

resource "aws_imagebuilder_infrastructure_configuration" "vdi" {
  name                          = "vdi-image-builder-infra"
  description                   = "プライベートサブネット内でビルド（インターネット不要）"
  instance_profile_name         = aws_iam_instance_profile.image_builder.name
  instance_types                = ["m5.large"]
  subnet_id                     = var.subnet_id
  security_group_ids            = [var.security_group_id]
  terminate_instance_on_failure = true

  logging {
    s3_logs {
      s3_bucket_name = aws_s3_bucket.image_builder_logs.bucket
      s3_key_prefix  = "image-builder/"
    }
  }
}

resource "aws_imagebuilder_distribution_configuration" "vdi" {
  name        = "vdi-distribution"
  description = "VDI Golden Image の配布設定"

  distribution {
    region = data.aws_region.current.region

    ami_distribution_configuration {
      name        = "vdi-golden-image-{{ imagebuilder:buildDate }}"
      description = "WorkSpaces Pools Golden Image"

      ami_tags = {
        Purpose = "WorkSpaces-VDI"
        Build   = "{{ imagebuilder:buildVersion }}"
      }
    }
  }
}

resource "aws_imagebuilder_image_pipeline" "vdi" {
  name                             = "vdi-golden-image-pipeline"
  description                      = "毎週 Windows Update を焼き込んで Golden Image を再ビルドするパイプライン"
  image_recipe_arn                 = aws_imagebuilder_image_recipe.vdi.arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.vdi.arn
  distribution_configuration_arn   = aws_imagebuilder_distribution_configuration.vdi.arn

  # パイプラインのネイティブスケジュールで毎週再ビルドする。
  # レシピ内の update-windows コンポーネントが最新パッチを適用するため、
  # 外部からの「Update 検知」トリガーは不要（旧 SSM Maintenance Window
  # 構成はターゲット不在で機能していなかった。review-log #4-1 参照）。
  # Image Builder の cron は UTC: 土曜 17:00 UTC = 日曜 02:00 JST
  schedule {
    schedule_expression                = "cron(0 17 ? * SAT *)"
    pipeline_execution_start_condition = "EXPRESSION_MATCH_ONLY"
  }

  status = "ENABLED"
}

# Image Builder 用 IAM
resource "aws_iam_role" "image_builder" {
  name = "vdi-image-builder-ec2"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "image_builder_core" {
  for_each = toset([
    "arn:aws:iam::aws:policy/EC2InstanceProfileForImageBuilder",
    "arn:aws:iam::aws:policy/EC2InstanceProfileForImageBuilderECRContainerBuilds",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ])
  role       = aws_iam_role.image_builder.name
  policy_arn = each.value
}

# AWS 管理ポリシーの S3 書込許可は "*imagebuilder*" 名のバケットに限られ、
# 本バケット名（vdi-image-builder-logs-*）はパターン一致しない。
# さらに SSE-KMS のため KMS 権限も必要 — 両方を明示付与する
resource "aws_iam_role_policy" "image_builder_logs" {
  name = "vdi-image-builder-log-write"
  role = aws_iam_role.image_builder.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.image_builder_logs.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource = [aws_kms_key.image_builder_logs.arn]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "image_builder" {
  name = "vdi-image-builder-profile"
  role = aws_iam_role.image_builder.name
}

# ビルドログ用 S3 バケット
resource "aws_kms_key" "image_builder_logs" {
  description         = "CMK for VDI Image Builder log bucket"
  enable_key_rotation = true
}

resource "aws_s3_bucket" "image_builder_logs" {
  bucket = "vdi-image-builder-logs-${data.aws_caller_identity.current.account_id}"
  # ビルドログは監査証跡。terraform destroy で消さない
  force_destroy = false
}

resource "aws_s3_bucket_server_side_encryption_configuration" "image_builder_logs" {
  bucket = aws_s3_bucket.image_builder_logs.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.image_builder_logs.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "image_builder_logs" {
  bucket                  = aws_s3_bucket.image_builder_logs.bucket
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# TLS 以外のアクセスを拒否（多層防御）
resource "aws_s3_bucket_policy" "image_builder_logs_tls_only" {
  bucket = aws_s3_bucket.image_builder_logs.bucket

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.image_builder_logs.arn,
        "${aws_s3_bucket.image_builder_logs.arn}/*",
      ]
      Condition = {
        Bool = { "aws:SecureTransport" = "false" }
      }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.image_builder_logs]
}
