"""
orchestrator.py — SSM Maintenance Window 完了後に Image Builder パイプラインを起動する。
EventBridge: SSM Maintenance Window Execution SUCCESS → この Lambda
"""
import json
import logging
import os
import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

imagebuilder = boto3.client("imagebuilder")


def handler(event, context):
    logger.info("SSM Maintenance Window completed. Starting Image Builder pipeline.")
    logger.info(json.dumps(event))

    pipeline_arn = os.environ["IMAGE_BUILDER_PIPELINE_ARN"]

    response = imagebuilder.start_image_pipeline_execution(
        imagePipelineArn=pipeline_arn
    )

    execution_id = response["imageBuildVersionArn"]
    logger.info(f"Image Builder pipeline started: {execution_id}")

    return {"status": "started", "imageBuildVersionArn": execution_id}
