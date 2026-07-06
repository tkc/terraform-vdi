# ══════════════════════════════════════════════════════════════════
# unit: ssm-patch — Golden Image 自動更新チェーンの起点
#
# 更新チェーン全体:
#   [このユニット] Maintenance Window（日曜 AM2:00）で Windows Update 適用
#     → EventBridge が完了(SUCCESS)を検知          [golden-image-updater]
#     → Lambda が Image Builder パイプライン起動    [image-builder]
#     → 新 AMI 完成 → Lambda が Pool を更新         [golden-image-updater]
# ══════════════════════════════════════════════════════════════════

resource "aws_ssm_patch_baseline" "windows" {
  name             = "vdi-windows-patch-baseline"
  operating_system = "WINDOWS"
  description      = "Windows patch baseline for VDI Golden Image"

  # Critical/Security は 7 日、一般 Updates は 14 日の様子見期間を置いてから自動承認
  approval_rule {
    approve_after_days = 7

    patch_filter {
      key    = "CLASSIFICATION"
      values = ["CriticalUpdates", "SecurityUpdates"]
    }

    patch_filter {
      key    = "MSRC_SEVERITY"
      values = ["Critical", "Important"]
    }
  }

  approval_rule {
    approve_after_days = 14

    patch_filter {
      key    = "CLASSIFICATION"
      values = ["Updates"]
    }
  }
}

resource "aws_ssm_default_patch_baseline" "windows" {
  baseline_id      = aws_ssm_patch_baseline.windows.id
  operating_system = "WINDOWS"
}

# Image Builder が使う EC2 インスタンスに適用する Maintenance Window
resource "aws_ssm_maintenance_window" "golden_image" {
  name                       = "vdi-golden-image-update"
  description                = "毎週日曜 AM2:00 に Windows Update を適用して Golden Image を更新"
  schedule                   = "cron(0 2 ? * SUN *)"
  duration                   = 4
  cutoff                     = 1
  allow_unassociated_targets = false
}

resource "aws_ssm_maintenance_window_target" "image_builder" {
  window_id     = aws_ssm_maintenance_window.golden_image.id
  name          = "image-builder-instances"
  resource_type = "INSTANCE"

  targets {
    key    = "tag:Purpose"
    values = ["ImageBuilder-VDI"]
  }
}

resource "aws_ssm_maintenance_window_task" "patch" {
  window_id        = aws_ssm_maintenance_window.golden_image.id
  task_type        = "RUN_COMMAND"
  task_arn         = "AWS-RunPatchBaseline"
  priority         = 1
  service_role_arn = aws_iam_role.ssm_maintenance.arn

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.image_builder.id]
  }

  task_invocation_parameters {
    run_command_parameters {
      document_hash_type = "Sha256"

      parameter {
        name   = "Operation"
        values = ["Install"]
      }

      parameter {
        name   = "RebootOption"
        values = ["RebootIfNeeded"]
      }
    }
  }
}

resource "aws_iam_role" "ssm_maintenance" {
  name = "vdi-ssm-maintenance-window"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ssm.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_maintenance" {
  role       = aws_iam_role.ssm_maintenance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonSSMMaintenanceWindowRole"
}
