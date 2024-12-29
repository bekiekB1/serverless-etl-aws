import boto3
import requests
import logging
import os
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def download_and_upload_to_s3(url: str, bucket: str, year_month: str) -> str:
    """Donwload the Data from url and upload to the bronze nyc bucket

    Args:
        url (str): url to download data from
        bucket (str): destination bronze bucket name
        year_month (str): processing month for raw data
                          (Nyc data update monthly Jan1, dec month data is available)

    Returns:
        str: final s3 uri(include file path in the bucket) 
    """
    try:
        logger.info(f"Downloading data from: {url}")

        response = requests.get(url, stream=True)
        response.raise_for_status()
        
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        key = f'nyc_taxi/yellow_taxi_{year_month}_{timestamp}.parquet'
        
        s3_client = boto3.client('s3')
        s3_client.upload_fileobj(response.raw, bucket, key)
        
        logger.info(f"Successfully uploaded data to s3://{bucket}/{key}")
        return key
        
    except Exception as e:
        logger.error(f"Error in download and upload: {str(e)}")
        raise

def lambda_handler(event, context):
    """_summary_

    Args:
        event (_type_): _description_
        context (_type_): _description_

    Raises:
        ValueError: _description_

    Returns:
        _type_: _description_
    """
    try:
        bucket_name = os.environ['BUCKET_NAME']
        
        url = event.get('url')
        year_month = event.get('year_month')
        
        if not url or not year_month:
            raise ValueError("Missing required parameters: 'url' or 'year_month'")
            
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