"""
pool_updater.py — Image Builder 完了後に WorkSpaces Pool の Golden Image を更新する。
EventBridge: EC2 Image Builder Image State Change (AVAILABLE) → この Lambda

処理チェーン:
  AMI 取得 → import_workspace_image → (AVAILABLE まで待機)
  → create_workspace_bundle → update_workspaces_pool

WorkSpaces は AMI を直接 Pool に適用できない。Image 取り込み → Bundle 作成
の 2 段を挟む必要がある（Bundle を経由しないと UpdateWorkspacesPool は失敗する）。

イメージ取り込みは長時間かかることがある。本 Lambda は冪等に作ってあり、
タイムアウト時は例外で終了 → EventBridge の非同期リトライ（最大 2 回）で
続きから再開する。それでも足りない環境では Step Functions 化を検討すること。
"""
import json
import logging
import os
import time

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

workspaces = boto3.client("workspaces")
imagebuilder = boto3.client("imagebuilder")

# 取り込みプロセスはライセンス形態・GPU 有無で変わる（環境依存のため環境変数で注入）。
# BYOL_REGULAR = BYOL の標準デスクトップ。GPU なら BYOL_GRAPHICS_G4DN 等
INGESTION_PROCESS = os.environ.get("INGESTION_PROCESS", "BYOL_REGULAR")
BUNDLE_COMPUTE_TYPE = os.environ.get("BUNDLE_COMPUTE_TYPE", "STANDARD")
# ストレージ容量は ComputeType と有効な組合せである必要がある（Terraform 変数で注入）
BUNDLE_USER_STORAGE = os.environ.get("BUNDLE_USER_STORAGE", "50")
BUNDLE_ROOT_STORAGE = os.environ.get("BUNDLE_ROOT_STORAGE", "80")

POLL_INTERVAL_SECONDS = 30
# タイムアウト前に安全に例外終了するためのマージン
DEADLINE_MARGIN_MS = 60_000


def get_ami_id(image_build_arn: str) -> str:
    """Image Builder のビルド版 ARN から成果物 AMI ID を得る。"""
    resp = imagebuilder.get_image(imageBuildVersionArn=image_build_arn)
    return resp["image"]["outputResources"]["amis"][0]["image"]


def image_name_for(ami_id: str) -> str:
    """AMI ごとに決定的な名前を割り当て、リトライ時の照合キーにする。"""
    return f"vdi-golden-{ami_id}"


def find_or_import_image(ami_id: str) -> tuple[str, str]:
    """冪等: 同じ AMI からの取り込みが既にあれば再利用する。"""
    name = image_name_for(ami_id)
    paginator = workspaces.get_paginator("describe_workspace_images")
    for page in paginator.paginate():
        for img in page["Images"]:
            if img["Name"] == name:
                logger.info(f"Reusing existing import {img['ImageId']} ({img['State']})")
                return img["ImageId"], img["State"]

    resp = workspaces.import_workspace_image(
        Ec2ImageId=ami_id,
        IngestionProcess=INGESTION_PROCESS,
        ImageName=name,
        ImageDescription="Auto-updated VDI Golden Image (SSM Patch → Image Builder)",
        Tags=[{"Key": "SourceAMI", "Value": ami_id}],
    )
    logger.info(f"Import started: {resp['ImageId']}")
    return resp["ImageId"], "PENDING"


def wait_until_image_available(image_id: str, context) -> None:
    """AVAILABLE まで待つ。Lambda の残り時間が尽きそうなら例外 → 非同期リトライへ。"""
    while True:
        resp = workspaces.describe_workspace_images(ImageIds=[image_id])
        state = resp["Images"][0]["State"]
        if state == "AVAILABLE":
            return
        if state == "ERROR":
            raise RuntimeError(f"Image {image_id} import failed")
        if context.get_remaining_time_in_millis() < DEADLINE_MARGIN_MS:
            raise TimeoutError(
                f"Image {image_id} still {state}; retry will resume idempotently"
            )
        logger.info(f"Image {image_id} is {state}; polling...")
        time.sleep(POLL_INTERVAL_SECONDS)


def find_or_create_bundle(image_id: str, ami_id: str) -> str:
    """冪等: 同名 Bundle があれば再利用。なければ Image から作成する。"""
    name = f"vdi-bundle-{ami_id}"
    # 自動更新のたびに Bundle が増えるため、必ず全ページ走査する
    # （1 ページ照合だと既存を見逃し、同名 Create が例外でチェーン停止する）
    paginator = workspaces.get_paginator("describe_workspace_bundles")
    for page in paginator.paginate(Owner="SELF"):
        for bundle in page["Bundles"]:
            if bundle["Name"] == name:
                logger.info(f"Reusing existing bundle {bundle['BundleId']}")
                return bundle["BundleId"]

    resp = workspaces.create_workspace_bundle(
        BundleName=name,
        BundleDescription="Auto-created from VDI Golden Image",
        ImageId=image_id,
        ComputeType={"Name": BUNDLE_COMPUTE_TYPE},
        UserStorage={"Capacity": BUNDLE_USER_STORAGE},
        RootStorage={"Capacity": BUNDLE_ROOT_STORAGE},
    )
    bundle_id = resp["WorkspaceBundle"]["BundleId"]
    logger.info(f"Bundle created: {bundle_id}")
    return bundle_id


def handler(event, context):
    logger.info(json.dumps(event))
    pool_id = os.environ["WORKSPACES_POOL_ID"]
    # "EC2 Image Builder Image State Change" イベントはビルド版 ARN を
    # resources[0] に載せる（detail には state しか入らない）
    image_build_arn = event["resources"][0]

    ami_id = get_ami_id(image_build_arn)
    logger.info(f"New AMI: {ami_id}")

    image_id, _state = find_or_import_image(ami_id)
    wait_until_image_available(image_id, context)
    bundle_id = find_or_create_bundle(image_id, ami_id)

    workspaces.update_workspaces_pool(PoolId=pool_id, BundleId=bundle_id)
    logger.info(f"Pool {pool_id} updated to bundle {bundle_id}")
    return {"status": "updated", "poolId": pool_id, "bundleId": bundle_id}
