# ══════════════════════════════════════════════════════════════════
# unit: golden-image-updater — 更新チェーンの接着剤（イベント駆動）
#
#   SSM Maintenance Window 完了 ─EventBridge→ orchestrator Lambda
#     → Image Builder パイプライン起動
#   Image Builder AMI 完成      ─EventBridge→ pool_updater Lambda
#     → WorkSpaces 画像インポート → Pool 更新
#
# 承認ゲートなしの完全自動。承認制にしたい場合は orchestrator の前に
# SNS + 手動承認を挿入する（docs/architecture.md 参照）。
# ══════════════════════════════════════════════════════════════════

data "archive_file" "orchestrator" {
  type        = "zip"
  source_file = "${path.module}/lambda/orchestrator.py"
  output_path = "${path.module}/lambda/orchestrator.zip"
}

data "archive_file" "pool_updater" {
  type        = "zip"
  source_file = "${path.module}/lambda/pool_updater.py"
  output_path = "${path.module}/lambda/pool_updater.zip"
}

# ── Lambda: orchestrator ────────────────────────────────────
resource "aws_lambda_function" "orchestrator" {
  function_name    = "vdi-golden-image-orchestrator"
  description      = "SSM Maintenance Window 完了 → Image Builder パイプライン起動"
  role             = aws_iam_role.lambda_orchestrator.arn
  handler          = "orchestrator.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.orchestrator.output_path
  source_code_hash = data.archive_file.orchestrator.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      IMAGE_BUILDER_PIPELINE_ARN = var.image_builder_pipeline_arn
    }
  }
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
  timeout          = 300 # 画像インポートに時間がかかるため

  environment {
    variables = {
      WORKSPACES_POOL_ID = var.workspaces_pool_id
    }
  }
}

# ── EventBridge: SSM Maintenance Window 完了 → orchestrator ──
resource "aws_cloudwatch_event_rule" "ssm_window_complete" {
  name        = "vdi-ssm-maintenance-window-complete"
  description = "SSM Maintenance Window 成功完了を検知して Image Builder を起動"

  # window-id で絞る: 他の Maintenance Window の完了で誤発火させない
  event_pattern = jsonencode({
    source      = ["aws.ssm"]
    detail-type = ["Maintenance Window Execution State-change Notification"]
    detail = {
      status      = ["SUCCESS"]
      "window-id" = [var.maintenance_window_id]
    }
  })
}

resource "aws_cloudwatch_event_target" "orchestrator" {
  rule      = aws_cloudwatch_event_rule.ssm_window_complete.name
  target_id = "invoke-orchestrator"
  arn       = aws_lambda_function.orchestrator.arn
}

resource "aws_lambda_permission" "allow_eventbridge_orchestrator" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.orchestrator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ssm_window_complete.arn
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

# ── IAM: orchestrator ────────────────────────────────────────
resource "aws_iam_role" "lambda_orchestrator" {
  name = "vdi-lambda-orchestrator"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_orchestrator" {
  name = "vdi-lambda-orchestrator-policy"
  role = aws_iam_role.lambda_orchestrator.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["imagebuilder:StartImagePipelineExecution"]
        Resource = [var.image_builder_pipeline_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
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
          "ec2:DescribeImages",
          "ec2:ModifyImageAttribute",
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}
