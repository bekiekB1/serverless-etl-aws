import json
import logging
import os
from datetime import datetime, timedelta

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ROOT_URL = "https://d37ci6vzurychx.cloudfront.net/trip-data/"


def get_monthly_url() -> str:
    """Generate URL for previous month's NYC taxi data

    Args:
        None

    Returns:
        str: URL for downloading previous month's taxi data
    """
    current_date = datetime.now()
    first_of_month = current_date.replace(day=1)
    last_month = first_of_month - timedelta(days=1)
    year_month = last_month.strftime("%Y-%m")
    return f"{ROOT_URL}yellow_tripdata_{year_month}.parquet"


def notify(subject: str, message: str) -> None:
    """Send SNS notification about processing status

    Args:
        subject (str): notification subject line
        message (str): detailed notification message

    Returns:
        None: sends SNS notification if topic ARN configured
    """
    try:
        sns = boto3.client("sns")
        topic_arn = os.environ.get("NOTIFICATION_TOPIC_ARN")
        if topic_arn:
            sns.publish(TopicArn=topic_arn, Subject=subject, Message=message)
    except Exception as e:
        logger.error(f"Failed to send notification: {str(e)}")


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Union[int, str]]:
    """Orchestrate fetching of new NYC taxi data

    Args:
        event (dict): Lambda event trigger
        context (object): Lambda context object

    Returns:
        dict: processing status and results
            statusCode (int): HTTP status code
            body (str): success/error message
    """
    try:
        url = get_monthly_url()
        logger.info(f"Generated URL: {url}")

        payload = {"url": url, "year_month": datetime.now().strftime("%Y-%m")}

        lambda_client = boto3.client("lambda")
        processor_response = lambda_client.invoke(
            FunctionName=os.environ["PROCESSOR_FUNCTION_NAME"], InvocationType="RequestResponse", Payload=json.dumps(payload)
        )

        response_payload = json.loads(processor_response["Payload"].read())
        logger.info(f"Processor response: {response_payload}")

        if processor_response["StatusCode"] == 200 and response_payload.get("statusCode") == 200:
            message = f"Successfully processed NYC taxi data for {payload['year_month']}"
            notify("NYC Taxi Data Processing Success", message)
            return {"statusCode": 200, "body": json.dumps(message)}
        else:
            error_message = f"Failed to process NYC taxi data: {response_payload}"
            notify("NYC Taxi Data Processing Failed", error_message)
            raise Exception(error_message)

    except Exception as e:
        error_message = f"Error in NYC taxi data processing: {str(e)}"
        logger.error(error_message)
        notify("NYC Taxi Data Processing Error", error_message)
        return {"statusCode": 500, "body": json.dumps(error_message)}
