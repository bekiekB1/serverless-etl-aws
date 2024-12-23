import boto3
import requests
import os
import json
from datetime import datetime

def lambda_handler(event, context):
    try:
        data_url = "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2024-01.parquet"
        
        response = requests.get(data_url, stream=True)
        if response.status_code != 200:
            raise Exception(f"Failed to download data. Status code: {response.status_code}")
        
        bucket_name = os.environ['BUCKET_NAME']
        
        current_time = datetime.now().strftime("%Y%m%d_%H%M%S")
        key = f'bronze/nyc_taxi/yellow_tripdata_{current_time}.parquet'
        
        # Upload directly to S3
        s3_client = boto3.client('s3')
        s3_client.upload_fileobj(response.raw, bucket_name, key)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Successfully uploaded file: {key}',
                'destination': f's3://{bucket_name}/{key}'
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Failed to process and upload NYC taxi data'
            })
        }
