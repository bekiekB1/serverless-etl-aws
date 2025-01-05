import json
import logging
import os
from datetime import datetime, timedelta
from typing import Any, Dict, Optional, Tuple, Union

import boto3
import requests
from botocore.exceptions import ClientError
from dateutil.relativedelta import relativedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ROOT_URL = "https://d37ci6vzurychx.cloudfront.net/trip-data/"


def check_url_exists(url: str) -> bool:
    """
    Check if the URL exists by making a HEAD request

    Args:
        url (str): URL to check

    Returns:
        bool: True if URL exists, False otherwise
    """
    try:
        response = requests.head(url, timeout=5)
        return response.status_code == 200
    except requests.RequestException:
        return False


def find_latest_available_data() -> Tuple[Optional[str], Optional[str]]:
    """
    Find the most recent available taxi data by checking URLs
    starting from two months ago and going backwards

    Returns:
        Tuple[Optional[str], Optional[str]]: (URL if found, year-month string) or (None, None) if not found
    """
    current_date = datetime.now()

    for months_back in range(2, 8):  # look for upto 6 months back for data
        check_date = current_date - relativedelta(months=months_back)
        year_month = check_date.strftime("%Y-%m")
        url = f"{ROOT_URL}yellow_tripdata_{year_month}.parquet"

        if check_url_exists(url):
            return url, year_month

    return None, None


def get_last_processed_date(table_name: str) -> Optional[str]:
    """
    Retrieve the last processed year-month from DynamoDB

    Args:
        table_name (str): DynamoDB table name

    Returns:
        Optional[str]: Last processed year-month or None if not found
    """
    try:
        dynamodb = boto3.resource("dynamodb")
        table = dynamodb.Table(table_name)
        response = table.get_item(Key={"id": "last_processed"})
        return response.get("Item", {}).get("year_month")
    except ClientError as e:
        logger.error(f"Error accessing DynamoDB: {str(e)}")
        return None


def update_last_processed_date(table_name: str, year_month: str) -> bool:
    """
    Update the last processed year-month in DynamoDB

    Args:
        table_name (str): DynamoDB table name
        year_month (str): Year-month string to store

    Returns:
        bool: True if successful, False otherwise
    """
    try:
        dynamodb = boto3.resource("dynamodb")
        table = dynamodb.Table(table_name)
        table.put_item(Item={"id": "last_processed", "year_month": year_month, "updated_at": datetime.now().isoformat()})
        return True
    except ClientError as e:
        logger.error(f"Error updating DynamoDB: {str(e)}")
        return False


def notify(subject: str, message: str) -> None:
    """
    Send SNS notification about processing status

    Args:
        subject (str): notification subject line
        message (str): detailed notification message
    """
    try:
        sns = boto3.client("sns")
        topic_arn = os.environ.get("NOTIFICATION_TOPIC_ARN")
        if topic_arn:
            sns.publish(TopicArn=topic_arn, Subject=subject, Message=message)
    except Exception as e:
        logger.error(f"Failed to send notification: {str(e)}")


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Union[int, str]]:
    """
    Orchestrate fetching of new NYC taxi data.

    Args:
        event (dict): Lambda event trigger
        context (object): Lambda context object

    Returns:
        dict: processing status and results
    """
    try:
        # Find the latest available data URL
        url, year_month = find_latest_available_data()
        if not url:
            message = "No new taxi data available within the last 6 months"
            notify("NYC Taxi Data Processing Skip", message)
            return {"statusCode": 200, "body": json.dumps(message)}

        # Check if we've already processed this month
        last_processed = get_last_processed_date(os.environ.get("DYNAMODB_TABLE_NAME", "nyc-taxi-processing"))
        if last_processed and last_processed >= year_month:
            message = f"Data for {year_month} has already been processed"
            notify("NYC Taxi Data Processing Skip", message)
            return {"statusCode": 200, "body": json.dumps(message)}

        # Process the data
        logger.info(f"Processing data for {year_month} from URL: {url}")
        payload = {"url": url, "year_month": year_month}

        lambda_client = boto3.client("lambda")
        processor_response = lambda_client.invoke(
            FunctionName=os.environ["PROCESSOR_FUNCTION_NAME"], InvocationType="RequestResponse", Payload=json.dumps(payload)
        )

        response_payload = json.loads(processor_response["Payload"].read())
        logger.info(f"Processor response: {response_payload}")

        if processor_response["StatusCode"] == 200 and response_payload.get("statusCode") == 200:
            # Update the last processed date
            if update_last_processed_date(os.environ.get("DYNAMODB_TABLE_NAME", "nyc-taxi-processing"), year_month):
                message = f"Successfully processed NYC taxi data for {year_month}"
                notify("NYC Taxi Data Processing Success", message)
                return {"statusCode": 200, "body": json.dumps(message)}
            else:
                raise Exception("Failed to update processing status in DynamoDB")
        else:
            error_message = f"Failed to process NYC taxi data: {response_payload}"
            notify("NYC Taxi Data Processing Failed", error_message)
            raise Exception(error_message)

    except Exception as e:
        error_message = f"Error in NYC taxi data processing: {str(e)}"
        logger.error(error_message)
        notify("NYC Taxi Data Processing Error", error_message)
        return {"statusCode": 500, "body": json.dumps(error_message)}
