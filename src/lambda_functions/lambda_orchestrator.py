import json
import boto3
import os
from datetime import datetime, timedelta
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def get_monthly_url():
    """Generate URL for the previous month's taxi data"""
    current_date = datetime.now()
    first_of_month = current_date.replace(day=1)
    last_month = first_of_month - timedelta(days=1)
    year_month = last_month.strftime("%Y-%m")
    return f"https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_{year_month}.parquet"

def notify(subject, message):
    """Send notification via SNS"""
    try:
        sns = boto3.client('sns')
        topic_arn = os.environ.get('NOTIFICATION_TOPIC_ARN')
        if topic_arn:
            sns.publish(
                TopicArn=topic_arn,
                Subject=subject,
                Message=message
            )
    except Exception as e:
        logger.error(f"Failed to send notification: {str(e)}")

def lambda_handler(event, context):
    try:
        # Get the URL for the current month's data
        url = get_monthly_url()
        logger.info(f"Generated URL: {url}")
        
        # Prepare the payload for the processor Lambda
        payload = {
            'url': url,
            'year_month': datetime.now().strftime("%Y-%m")
        }
        
        # Invoke the processor Lambda
        lambda_client = boto3.client('lambda')
        processor_response = lambda_client.invoke(
            FunctionName=os.environ['PROCESSOR_FUNCTION_NAME'],
            InvocationType='RequestResponse',
            Payload=json.dumps(payload)
        )
        
        # Parse the response
        response_payload = json.loads(processor_response['Payload'].read())
        logger.info(f"Processor response: {response_payload}")
        
        # Check if processing was successful
        if processor_response['StatusCode'] == 200 and response_payload.get('statusCode') == 200:
            message = f"Successfully processed NYC taxi data for {payload['year_month']}"
            notify("NYC Taxi Data Processing Success", message)
            return {
                'statusCode': 200,
                'body': json.dumps(message)
            }
        else:
            error_message = f"Failed to process NYC taxi data: {response_payload}"
            notify("NYC Taxi Data Processing Failed", error_message)
            raise Exception(error_message)
            
    except Exception as e:
        error_message = f"Error in NYC taxi data processing: {str(e)}"
        logger.error(error_message)
        notify("NYC Taxi Data Processing Error", error_message)
        return {
            'statusCode': 500,
            'body': json.dumps(error_message)
        }