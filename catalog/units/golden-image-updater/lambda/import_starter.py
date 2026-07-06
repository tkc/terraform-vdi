"""
import_starter.py — Image Builder の成果物 AMI を WorkSpaces イメージとして
インポート開始する（Step Functions の第 1 ステート）。

インポートは非同期で 45 分前後かかるため、完了待ちはここでは行わない。
完了確認〜Bundle 作成〜Pool 更新は import_finalizer.py が担う。
"""
import logging
import os

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

imagebuilder = boto3.client("imagebuilder")
workspaces = boto3.client("workspaces")


def handler(event, context):
    # EventBridge の Image Builder イベントがそのまま入力される。
    # ビルド版 ARN は resources[0]（例: .../image/vdi-golden-image/1.0.0/3）
    image_build_arn = event["resources"][0]
    logger.info(f"Image build completed: {image_build_arn}")

    image = imagebuilder.get_image(imageBuildVersionArn=image_build_arn)["image"]
    ami_id = image["outputResources"]["amis"][0]["image"]
    logger.info(f"Output AMI: {ami_id}")

    # ARN 末尾の <version>/<build> から一意なイメージ名を作る（例: 1-0-0-3）
    version_suffix = "-".join(image_build_arn.split("/")[-2:]).replace(".", "-")

    response = workspaces.import_workspace_image(
        Ec2ImageId=ami_id,
        # WorkSpaces Pools は BYOP 系インジェストが必要。
        # Bundle の種類を変える場合は Terraform 側の環境変数を更新する
        IngestionProcess=os.environ["INGESTION_PROCESS"],
        ImageName=f"vdi-golden-image-{version_suffix}",
        ImageDescription="Auto-updated VDI Golden Image (SSM Patch + Image Builder)",
        Tags=[
            {"Key": "AutoUpdated", "Value": "true"},
            {"Key": "SourceAMI", "Value": ami_id},
        ],
    )

    workspace_image_id = response["ImageId"]
    logger.info(f"WorkSpaces image import started: {workspace_image_id}")

    # Step Functions の次ステート（import_finalizer）への入力
    return {"workspace_image_id": workspace_image_id, "source_ami": ami_id}
