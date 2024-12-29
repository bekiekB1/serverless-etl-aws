import json
from datetime import datetime
from typing import Any, Dict, List, Optional, Union

import boto3


class S3FileProcessor:
    def __init__(self):
        self.s3 = boto3.client("s3")
        self.cloudwatch = boto3.client("cloudwatch")

    def get_unprocessed_files(self, bucket: str, prefix: str) -> List[str]:
        """Retrieve list of unprocessed files from S3 bucket

        Args:
            bucket (str): source S3 bucket name
            prefix (str): S3 prefix to filter files

        Returns:
            list: list of unprocessed file keys
        """
        unprocessed_files = []

        paginator = self.s3.get_paginator("list_objects_v2")
        for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
            if "Contents" in page:
                for obj in page["Contents"]:
                    try:
                        response = self.s3.get_object_tagging(Bucket=bucket, Key=obj["Key"])
                        tags = {tag["Key"]: tag["Value"] for tag in response.get("TagSet", [])}

                        if "ProcessingStatus" not in tags or tags["ProcessingStatus"] != "Processed":
                            unprocessed_files.append(obj["Key"])
                    except self.s3.exceptions.NoSuchKey:
                        continue

        return unprocessed_files

    def mark_as_processed(self, bucket: str, key: str, status: str = "Processed", error: Optional[str] = None) -> None:
        """Mark S3 file with processing status via tags

        Args:
            bucket (str): S3 bucket name
            key (str): S3 object key
            status (str): processing status tag value (default: Processed)
            error (str): error message if processing failed (default: None)

        Returns:
            None: updates S3 object tags
        """
        tags = [{"Key": "ProcessingStatus", "Value": status}, {"Key": "ProcessedDate", "Value": datetime.now().isoformat()}]
        if error:
            tags.append({"Key": "Error", "Value": str(error)[:250]})

        self.s3.put_object_tagging(Bucket=bucket, Key=key, Tagging={"TagSet": tags})

    def archive_file(self, bucket: str, key: str) -> None:
        """Move processed file to archive location

        Args:
            bucket (str): S3 bucket name
            key (str): S3 object key to archive

        Returns:
            None: moves file to archive prefix
        """
        date_prefix = datetime.now().strftime("%Y/%m/%d")
        archive_key = f"archive/{date_prefix}/{key.split('/')[-1]}"

        self.s3.copy_object(Bucket=bucket, Key=archive_key, CopySource={"Bucket": bucket, "Key": key})
        self.s3.delete_object(Bucket=bucket, Key=key)


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Union[int, Union[str, Dict[str, List[str]]]]]:
    """Handle S3 file processing operations

    Args:
        event (dict): Lambda event with action and file details
            action (str): operation to perform (get_unprocessed/mark_processed/archive)
            bucket (str): S3 bucket name
            key (str): S3 object key (for mark_processed/archive)
            prefix (str): S3 prefix (for get_unprocessed)
        context (object): Lambda context object

    Returns:
        dict: operation results
            statusCode (int): HTTP status code
            body (str/dict): operation results or error message
    """
    processor = S3FileProcessor()

    action = event["action"]
    bucket = event["bucket"]

    try:
        if action == "get_unprocessed":
            prefix = event["prefix"]
            files = processor.get_unprocessed_files(bucket, prefix)
            return {"statusCode": 200, "body": {"unprocessed_files": files}}

        elif action == "mark_processed":
            key = event["key"]
            status = event.get("status", "Processed")
            error = event.get("error")
            processor.mark_as_processed(bucket, key, status, error)
            return {"statusCode": 200, "body": f"Marked {key} as {status}"}

        elif action == "archive":
            key = event["key"]
            processor.archive_file(bucket, key)
            return {"statusCode": 200, "body": f"Archived {key}"}

        else:
            return {"statusCode": 400, "body": f"Unknown action: {action}"}

    except Exception as e:
        return {"statusCode": 500, "body": str(e)}
