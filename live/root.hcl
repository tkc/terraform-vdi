# ══════════════════════════════════════════════════════════════════
# root.hcl — live/ 配下すべての Terragrunt 共通設定
#
# ここで backend（S3 + DynamoDB ロック）・provider・versions を一元生成する。
# 各環境ディレクトリの terragrunt.stack.hcl は include するだけ。
# ══════════════════════════════════════════════════════════════════

locals {
  account_id = get_aws_account_id()
  region     = "ap-northeast-1"
}

remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket         = "tfstate-vdi-${local.account_id}"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = local.region
    encrypt        = true
    dynamodb_table = "tfstate-lock-vdi"
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "${local.region}"

  default_tags {
    tags = {
      Project     = "vdi"
      ManagedBy   = "terragrunt"
      Environment = "prod"
    }
  }
}

# awscc（WorkSpaces Pools 用）にも明示的に region を渡す。
# 未設定だと環境変数頼みになり、クリーン環境の plan が失敗する
provider "awscc" {
  region = "${local.region}"
}
EOF
}

generate "versions" {
  path      = "versions.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
    awscc = {
      source  = "hashicorp/awscc"
      version = "~> 1.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}
EOF
}
