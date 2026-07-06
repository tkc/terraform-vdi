# ══════════════════════════════════════════════════════════════════
# unit: vpc — VDI 基盤のネットワーク土台
#
# 設計方針: 完全閉鎖網。パブリックサブネット・IGW・NAT を一切作らない。
# AWS API への到達は VPC エンドポイント経由のみ。
# 他アカウントへの経路は tgw-attachment ユニットが追加する。
# ══════════════════════════════════════════════════════════════════

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
}

# プライベートサブネット × 2 AZ。
# Managed AD と WorkSpaces がともに「異なる AZ の 2 サブネット」を要求するため 2 固定
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "vdi-private-${count.index + 1}"
  }
}

resource "aws_route_table" "private" {
  count  = 2
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "vdi-private-rt-${count.index + 1}"
  }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# ── VPC エンドポイント ──────────────────────────────────────────
# インターネット遮断環境で各 AWS サービスに到達するための唯一の経路。
# ここに無いサービスを新たに使う場合はエンドポイント追加が必要
locals {
  interface_endpoints = [
    "ssm",
    "ssmmessages",
    "ec2messages",
    "workspaces",
    "imagebuilder",
    "lambda",
    "events",
  ]
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(local.interface_endpoints)

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id
}

resource "aws_security_group" "vpc_endpoints" {
  name        = "vdi-vpc-endpoints"
  description = "Allow HTTPS from VPC for VPC endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
}

resource "aws_security_group" "workspaces" {
  name        = "vdi-workspaces"
  description = "WorkSpaces Pools instances"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "HTTPS to VPC endpoints"
  }

  egress {
    from_port   = 389
    to_port     = 389
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "LDAP to Managed AD"
  }

  egress {
    from_port   = 636
    to_port     = 636
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "LDAPS to Managed AD"
  }

  # 接続先サービスの必要ポートのみ許可（全ポート開放にしない）
  dynamic "egress" {
    for_each = toset([for p in var.other_account_ports : tostring(p)])
    content {
      from_port   = tonumber(egress.value)
      to_port     = tonumber(egress.value)
      protocol    = "tcp"
      cidr_blocks = var.other_account_cidrs
      description = "Port ${egress.value} to other AWS accounts via TGW"
    }
  }
}

resource "aws_security_group" "managed_ad" {
  name        = "vdi-managed-ad"
  description = "AWS Managed Microsoft AD"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 389
    to_port         = 389
    protocol        = "tcp"
    security_groups = [aws_security_group.workspaces.id]
  }

  ingress {
    from_port       = 636
    to_port         = 636
    protocol        = "tcp"
    security_groups = [aws_security_group.workspaces.id]
  }

  ingress {
    from_port       = 53
    to_port         = 53
    protocol        = "udp"
    security_groups = [aws_security_group.workspaces.id]
  }
}
