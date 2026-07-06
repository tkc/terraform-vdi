terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.86" # data.aws_region の region 属性を使うため
    }
  }
}
