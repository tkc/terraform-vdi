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
# キーを「rt インデックス + CIDR」にすることで、CIDR の追加・削除時に
# 無関係なルートが再作成されない（count の直積だと index がずれて全再作成になる）
locals {
  tgw_routes = {
    for pair in setproduct(range(length(var.route_table_ids)), var.other_account_cidrs) :
    "rt${pair[0]}-${pair[1]}" => {
      route_table_id = var.route_table_ids[pair[0]]
      cidr           = pair[1]
    }
  }
}

resource "aws_route" "to_other_accounts" {
  for_each = local.tgw_routes

  route_table_id         = each.value.route_table_id
  destination_cidr_block = each.value.cidr
  transit_gateway_id     = data.aws_ec2_transit_gateway.shared.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.main]
}
