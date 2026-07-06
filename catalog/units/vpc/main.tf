# ══════════════════════════════════════════════════════════════════
# unit: vpc — VDI 基盤のネットワーク土台
#
# 設計方針: 完全閉鎖網。パブリックサブネット・IGW・NAT を一切作らない。
# AWS API への到達は VPC エンドポイント経由のみ。
# 他アカウントへの経路は tgw-attachment ユニットが追加する。
# ══════════════════════════════════════════════════════════════════

# region は provider 設定から導出（root.hcl と変数の二重管理をしない）
data "aws_region" "current" {}

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
  service_name        = "com.amazonaws.${data.aws_region.current.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
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

# AD ドメイン参加・GPO・Kerberos 認証に必要な通信ポートセット。
# LDAP だけではドメイン参加は成立しない（review-log #9-2）
locals {
  ad_ports = {
    dns_tcp      = { from = 53, to = 53, proto = "tcp", desc = "DNS to Managed AD" }
    dns_udp      = { from = 53, to = 53, proto = "udp", desc = "DNS to Managed AD" }
    kerberos_tcp = { from = 88, to = 88, proto = "tcp", desc = "Kerberos" }
    kerberos_udp = { from = 88, to = 88, proto = "udp", desc = "Kerberos" }
    ntp_udp      = { from = 123, to = 123, proto = "udp", desc = "NTP (time sync for Kerberos)" }
    rpc_tcp      = { from = 135, to = 135, proto = "tcp", desc = "RPC endpoint mapper" }
    ldap_tcp     = { from = 389, to = 389, proto = "tcp", desc = "LDAP" }
    smb_tcp      = { from = 445, to = 445, proto = "tcp", desc = "SMB (GPO / SYSVOL)" }
    kpasswd_tcp  = { from = 464, to = 464, proto = "tcp", desc = "Kerberos password change" }
    kpasswd_udp  = { from = 464, to = 464, proto = "udp", desc = "Kerberos password change" }
    ldaps_tcp    = { from = 636, to = 636, proto = "tcp", desc = "LDAPS" }
    gc_tcp       = { from = 3268, to = 3269, proto = "tcp", desc = "LDAP Global Catalog" }
    rpc_dyn_tcp  = { from = 49152, to = 65535, proto = "tcp", desc = "RPC dynamic range" }
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

  # AD 通信ポートセット（宛先は VPC 内 = Managed AD の ENI）
  dynamic "egress" {
    for_each = local.ad_ports
    content {
      from_port   = egress.value.from
      to_port     = egress.value.to
      protocol    = egress.value.proto
      cidr_blocks = [var.vpc_cidr]
      description = egress.value.desc
    }
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

# Image Builder のビルドインスタンス専用 SG（WorkSpaces 用 SG と役割分離）。
# 必要なのは SSM 経由の制御（VPC エンドポイント 443）と
# S3（ログ書込・インストーラー取得。Gateway 型のため prefix list 宛の許可が必要）
resource "aws_security_group" "image_builder" {
  name        = "vdi-image-builder"
  description = "Image Builder build instances"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "HTTPS to VPC interface endpoints (SSM etc.)"
  }

  egress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [aws_vpc_endpoint.s3.prefix_list_id]
    description     = "HTTPS to S3 via gateway endpoint (build logs / installers)"
  }
}
