# ══════════════════════════════════════════════════════════════════
# stack: vdi-core — 8 ユニットの依存関係と配線を一元管理
#
# ユニット間の outputs → inputs の受け渡しはすべてここに集約。
# 環境固有の値は live/<env>/.../stack_vars.hcl から読む（このファイルは
# 環境非依存に保つ）。依存グラフは docs/architecture.md 参照。
# ══════════════════════════════════════════════════════════════════

locals {
  # live/ から渡される変数
  vars = read_terragrunt_config(find_in_parent_folders("stack_vars.hcl"))
}

unit "vpc" {
  source = "${get_repo_root()}/catalog/units/vpc"

  inputs = {
    vpc_cidr            = local.vars.locals.vpc_cidr
    region              = local.vars.locals.region
    other_account_cidrs = local.vars.locals.other_account_cidrs
    other_account_ports = local.vars.locals.other_account_ports
  }
}

unit "managed_ad" {
  source = "${get_repo_root()}/catalog/units/managed-ad"

  depends_on = [unit.vpc]

  inputs = {
    domain_name            = local.vars.locals.ad_domain_name
    ad_password_secret_arn = local.vars.locals.ad_password_secret_arn
    vpc_id                 = unit.vpc.outputs.vpc_id
    subnet_ids             = unit.vpc.outputs.private_subnet_ids
  }
}

unit "tgw_attachment" {
  source = "${get_repo_root()}/catalog/units/tgw-attachment"

  depends_on = [unit.vpc]

  inputs = {
    transit_gateway_id  = local.vars.locals.transit_gateway_id
    vpc_id              = unit.vpc.outputs.vpc_id
    subnet_ids          = unit.vpc.outputs.private_subnet_ids
    route_table_ids     = unit.vpc.outputs.private_route_table_ids
    other_account_cidrs = local.vars.locals.other_account_cidrs
  }
}

unit "saml_provider" {
  source = "${get_repo_root()}/catalog/units/saml-provider"
}

unit "workspaces_pools" {
  source = "${get_repo_root()}/catalog/units/workspaces-pools"

  depends_on = [unit.managed_ad, unit.saml_provider]

  inputs = {
    directory_id          = unit.managed_ad.outputs.directory_id
    subnet_ids            = unit.vpc.outputs.private_subnet_ids
    bundle_id             = local.vars.locals.workspaces_bundle_id
    pool_name             = local.vars.locals.pool_name
    workspace_access_url  = local.vars.locals.workspace_access_url
    max_user_sessions     = local.vars.locals.max_user_sessions
  }
}

unit "ssm_patch" {
  source = "${get_repo_root()}/catalog/units/ssm-patch"
}

unit "image_builder" {
  source = "${get_repo_root()}/catalog/units/image-builder"

  depends_on = [unit.vpc]

  inputs = {
    subnet_id         = unit.vpc.outputs.private_subnet_ids[0]
    security_group_id = unit.vpc.outputs.sg_workspaces_id
  }
}

unit "golden_image_updater" {
  source = "${get_repo_root()}/catalog/units/golden-image-updater"

  depends_on = [unit.image_builder, unit.workspaces_pools, unit.ssm_patch]

  inputs = {
    image_builder_pipeline_arn = unit.image_builder.outputs.pipeline_arn
    workspaces_pool_id         = unit.workspaces_pools.outputs.pool_id
    maintenance_window_id      = unit.ssm_patch.outputs.maintenance_window_id
    image_arn_prefix           = unit.image_builder.outputs.image_arn_prefix
  }
}
