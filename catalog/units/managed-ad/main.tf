data "aws_secretsmanager_secret_version" "ad_password" {
  secret_id = var.ad_password_secret_arn
}

resource "aws_directory_service_directory" "main" {
  name     = var.domain_name
  password = data.aws_secretsmanager_secret_version.ad_password.secret_string
  edition  = "Standard"
  type     = "MicrosoftAD"

  vpc_settings {
    vpc_id     = var.vpc_id
    subnet_ids = var.subnet_ids
  }
}
