import boto3
import requests
import logging
import os
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def download_and_upload_to_s3(url: str, bucket: str, year_month: str) -> str:
    """
    Download data from URL and directly upload to S3
    """
    try:
        logger.info(f"Downloading data from: {url}")
        
        # Stream the download
        response = requests.get(url, stream=True)
        response.raise_for_status()
        
        # Generate S3 key
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        key = f'nyc_taxi/yellow_taxi_{year_month}_{timestamp}.parquet'
        
        # Upload to S3 using the streaming response
        s3_client = boto3.client('s3')
        s3_client.upload_fileobj(response.raw, bucket, key)
        
        logger.info(f"Successfully uploaded data to s3://{bucket}/{key}")
        return key
        
    except Exception as e:
        logger.error(f"Error in download and upload: {str(e)}")
        raise

def lambda_handler(event, context):
    """
    Main Lambda handler
    """
    try:
        # Get environment variables
        bucket_name = os.environ['BUCKET_NAME']
        
        # Get URL and year_month from event
        url = event.get('url')
        year_month = event.get('year_month')
        
        if not url or not year_month:
            raise ValueError("Missing required parameters: 'url' or 'year_month'")
            
        # Download and upload to S3
        s3_key = download_and_upload_to_s3(url, bucket_name, year_month)
        
        return {
            'statusCode': 200,
            'body': {
                'message': 'Successfully downloaded and uploaded data',
                'bucket': bucket_name,
                'key': s3_key,
                'year_month': year_month
            }
        }
        
    except ValueError as e:
        logger.error(f"Validation error: {str(e)}")
        return {
            'statusCode': 400,
            'body': {
                'error': str(e),
                'message': 'Invalid input parameters'
            }
        }
        
    except Exception as e:
        logger.error(f"Error processing taxi data: {str(e)}")
        return {
            'statusCode': 500,
            'body': {
                'error': str(e),
                'message': 'Failed to process taxi data'
            }
        }