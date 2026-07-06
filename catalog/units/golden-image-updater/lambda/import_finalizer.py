"""
import_finalizer.py — WorkSpaces イメージのインポート完了を確認し、
Bundle を作成して Pool を更新する（Step Functions の第 2 ステート）。

ポーリング設計: インポートが未完了なら ImageNotReadyError を投げる。
Step Functions 側の Retry（5 分間隔 × 最大 36 回 = 最長 3 時間）が
再実行することで、Lambda の 15 分制限を超える完了待ちを実現する。
"""
import logging
import os

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

workspaces = boto3.client("workspaces")


class ImageNotReadyError(Exception):
    """インポート未完了。Step Functions の Retry 対象。"""


def handler(event, context):
    image_id = event["workspace_image_id"]

    image = workspaces.describe_workspace_images(ImageIds=[image_id])["Images"][0]
    state = image["State"]
    logger.info(f"Image {image_id} state: {state}")

    if state == "PENDING":
        raise ImageNotReadyError(f"{image_id} is still importing")
    if state == "ERROR":
        raise RuntimeError(
            f"Image import failed: {image.get('ErrorCode', '')} "
            f"{image.get('ErrorMessage', '')}"
        )

    # AVAILABLE — Pool は Bundle 単位でしか画像を切り替えられないため、
    # イメージから Bundle を作成してから Pool を更新する
    bundle = workspaces.create_workspace_bundle(
        BundleName=f"vdi-bundle-{image_id}",
        BundleDescription="Auto-created from VDI golden image",
        ImageId=image_id,
        ComputeType={"Name": os.environ["COMPUTE_TYPE"]},
        UserStorage={"Capacity": os.environ["USER_STORAGE_GB"]},
        RootStorage={"Capacity": os.environ["ROOT_STORAGE_GB"]},
    )["WorkspaceBundle"]

    bundle_id = bundle["BundleId"]
    logger.info(f"Bundle created: {bundle_id}")

    pool_id = os.environ["WORKSPACES_POOL_ID"]
    workspaces.update_workspaces_pool(PoolId=pool_id, BundleId=bundle_id)
    logger.info(f"Pool {pool_id} updated to bundle {bundle_id}")

    return {"pool_id": pool_id, "bundle_id": bundle_id, "image_id": image_id}
