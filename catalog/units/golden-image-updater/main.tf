# ══════════════════════════════════════════════════════════════════
# unit: golden-image-updater — Golden Image 完成を Pool に反映（イベント駆動）
#
#   Image Builder パイプライン（週次スケジュール + 依存更新検知は
#   image-builder ユニット側で完結）
#     → AMI 完成 ─EventBridge→ pool_updater Lambda
#     → WorkSpaces 画像インポート → Bundle 作成 → Pool 更新
#
# 承認ゲートなしの完全自動。承認制にしたい場合は pool_updater の前に
# SNS + 手動承認を挿入する（docs/architecture.md 参照）。
# ══════════════════════════════════════════════════════════════════

data "archive_file" "pool_updater" {
  type        = "zip"
  source_file = "${path.module}/lambda/pool_updater.py"
  output_path = "${path.module}/lambda/pool_updater.zip"
}

# ── 失敗時の最終防衛: DLQ + アラーム ─────────────────────────
# EventBridge の非同期リトライ（2 回）を使い切ったイベントを DLQ に保全し、
# アラームで通知する。これが無いと Pool が古いイメージのまま誰も気づけない
resource "aws_sqs_queue" "pool_updater_dlq" {
  name                      = "vdi-pool-updater-dlq"
  message_retention_seconds = 1209600 # 14 日（手動リカバリの猶予）
  sqs_managed_sse_enabled   = true
}

# SNS 暗号化用 CMK。AWS 管理キー（alias/aws/sns）はキーポリシーを変更できず
# CloudWatch アラームが発行に失敗するため、CMK + 明示のキーポリシーにする
resource "aws_kms_key" "alerts" {
  description         = "CMK for VDI alert SNS topic"
  enable_key_rotation = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowAccountAdmin"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowCloudWatchAlarms"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = ["kms:Decrypt", "kms:GenerateDataKey*"]
        Resource  = "*"
      }
    ]
  })
}

data "aws_caller_identity" "current" {}

resource "aws_sns_topic" "alerts" {
  name              = "vdi-golden-image-alerts"
  kms_master_key_id = aws_kms_key.alerts.arn
}

# alert_email が設定されている場合のみメール購読を作成
resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "pool_updater_errors" {
  alarm_name          = "vdi-pool-updater-errors"
  alarm_description   = "Golden Image の Pool 反映 Lambda が失敗（runbook.md 参照）"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.pool_updater.function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  alarm_name          = "vdi-pool-updater-dlq-not-empty"
  alarm_description   = "Pool 反映イベントがリトライを使い切って DLQ に滞留（runbook.md 参照）"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.pool_updater_dlq.name }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

# ── Lambda: pool_updater ────────────────────────────────────
resource "aws_lambda_function" "pool_updater" {
  function_name    = "vdi-workspaces-pool-updater"
  description      = "Image Builder 完了 → WorkSpaces Pool の Golden Image を更新"
  role             = aws_iam_role.lambda_pool_updater.arn
  handler          = "pool_updater.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.pool_updater.output_path
  source_code_hash = data.archive_file.pool_updater.output_base64sha256
  # 画像取り込みの待機があるため Lambda 上限いっぱい。
  # 足りない分は冪等リトライ（EventBridge 非同期×2）で続きから再開する
  timeout = 900

  dead_letter_config {
    target_arn = aws_sqs_queue.pool_updater_dlq.arn
  }

  environment {
    variables = {
      WORKSPACES_POOL_ID  = var.workspaces_pool_id
      INGESTION_PROCESS   = var.ingestion_process
      BUNDLE_COMPUTE_TYPE = var.bundle_compute_type
      BUNDLE_USER_STORAGE = tostring(var.bundle_user_storage_gb)
      BUNDLE_ROOT_STORAGE = tostring(var.bundle_root_storage_gb)
    }
  }
}

# ── EventBridge: Image Builder 完了 → pool_updater ──────────
resource "aws_cloudwatch_event_rule" "image_builder_complete" {
  name        = "vdi-image-builder-complete"
  description = "EC2 Image Builder パイプライン完了を検知して WorkSpaces Pool を更新"

  # resources の ARN プレフィックスで絞る:
  # 無関係なパイプラインのイメージ完成で Pool が書き換わる事故を防ぐ
  event_pattern = jsonencode({
    source      = ["aws.imagebuilder"]
    detail-type = ["EC2 Image Builder Image State Change"]
    resources   = [{ prefix = var.image_arn_prefix }]
    detail = {
      state = {
        status = ["AVAILABLE"]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "pool_updater" {
  rule      = aws_cloudwatch_event_rule.image_builder_complete.name
  target_id = "invoke-pool-updater"
  arn       = aws_lambda_function.pool_updater.arn
}

resource "aws_lambda_permission" "allow_eventbridge_pool_updater" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pool_updater.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.image_builder_complete.arn
}

# ── IAM: pool_updater ────────────────────────────────────────
resource "aws_iam_role" "lambda_pool_updater" {
  name = "vdi-lambda-pool-updater"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_pool_updater" {
  name = "vdi-lambda-pool-updater-policy"
  role = aws_iam_role.lambda_pool_updater.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "imagebuilder:GetImage",
          "workspaces:UpdateWorkspacesPool",
          "workspaces:ImportWorkspaceImage",
          "workspaces:DescribeWorkspaceImages",
          "workspaces:CreateWorkspaceBundle",
          "workspaces:DescribeWorkspaceBundles",
          # ec2:* の 2 つは ImportWorkspaceImage の内部要件（AMI 共有のため）
          "ec2:DescribeImages",
          "ec2:ModifyImageAttribute",
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = [aws_sqs_queue.pool_updater_dlq.arn]
      }
    ]
  })
}
