"""
pool_updater.py — Image Builder パイプライン完了後に WorkSpaces Pool の画像を更新する。
EventBridge: EC2 Image Builder Image State Change (AVAILABLE) → この Lambda
"""
import json
import logging
import os
import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

workspaces = boto3.client("workspaces")
ec2 = boto3.client("ec2")


def get_ami_id_from_build_arn(image_build_arn: str) -> str:
    """Image Builder の成果物 ARN から AMI ID を取得する。"""
    imagebuilder = boto3.client("imagebuilder")
    response = imagebuilder.get_image(imageBuildVersionArn=image_build_arn)
    ami_id = response["image"]["outputResources"]["amis"][0]["image"]
    return ami_id


def handler(event, context):
    logger.info("Image Builder pipeline completed. Updating WorkSpaces Pool.")
    logger.info(json.dumps(event))

    pool_id = os.environ["WORKSPACES_POOL_ID"]
    image_build_arn = event["detail"]["imageBuildVersionArn"]

    # AMI ID を取得
    ami_id = get_ami_id_from_build_arn(image_build_arn)
    logger.info(f"New AMI ID: {ami_id}")

    # WorkSpaces 用カスタムイメージを作成
    # (WorkSpaces Pool はカスタムイメージとして登録が必要)
    import_response = workspaces.import_workspace_image(
        Ec2ImageId=ami_id,
        IngestionProcess="BYOL_GRAPHICS_G4DN",
        ImageName=f"vdi-golden-image-{context.aws_request_id[:8]}",
        ImageDescription="Auto-updated VDI Golden Image via SSM Patch + Image Builder",
        Tags=[
            {"Key": "AutoUpdated", "Value": "true"},
            {"Key": "SourceAMI", "Value": ami_id},
        ],
    )

    ws_image_id = import_response["ImageId"]
    logger.info(f"WorkSpaces image imported: {ws_image_id}")

    # Pool を新しい画像に更新
    workspaces.update_workspaces_pool(
        PoolId=pool_id,
        BundleId=ws_image_id,  # カスタム画像で Pool を更新
    )

    logger.info(f"WorkSpaces Pool {pool_id} updated to image {ws_image_id}")
    return {"status": "updated", "poolId": pool_id, "newImageId": ws_image_id}
