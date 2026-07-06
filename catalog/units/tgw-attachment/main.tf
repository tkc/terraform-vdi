# ══════════════════════════════════════════════════════════════════
# unit: tgw-attachment — 他 AWS アカウントへの閉鎖網経路
#
# Transit Gateway 本体は接続先アカウントが所有し、RAM でこのアカウントに
# 共有されている前提。このユニットは「アタッチメント + ルート」だけを管理する。
# TGW ルートテーブル側の設定（戻り経路）は接続先アカウントの責任範囲。
# ══════════════════════════════════════════════════════════════════

data "aws_ec2_transit_gateway" "shared" {
  filter {
    name   = "transit-gateway-id"
    values = [var.transit_gateway_id]
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "main" {
  transit_gateway_id = data.aws_ec2_transit_gateway.shared.id
  vpc_id             = var.vpc_id
  subnet_ids         = var.subnet_ids

  dns_support  = "enable"
  ipv6_support = "disable"

  tags = {
    Name = "vdi-tgw-attachment"
  }
}

# プライベートサブネットの各ルートテーブルに他アカウント CIDR → TGW のルートを追加。
# (ルートテーブル数 × CIDR 数) の直積を count で展開している
resource "aws_route" "to_other_accounts" {
  count = length(var.route_table_ids) * length(var.other_account_cidrs)

  route_table_id         = var.route_table_ids[count.index % length(var.route_table_ids)]
  destination_cidr_block = var.other_account_cidrs[floor(count.index / length(var.route_table_ids))]
  transit_gateway_id     = data.aws_ec2_transit_gateway.shared.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.main]
}
