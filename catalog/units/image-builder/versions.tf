terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      # data.aws_region の region 属性を使うため 5.86 以降が必要
      source  = "hashicorp/aws"
      version = ">= 5.86"
    }
  }
}
