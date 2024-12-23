import pandas as pd
import boto3
from io import BytesIO
import os
import json
from datetime import datetime

def lambda_handler(event, context):
    try:
        # Create a simple test DataFrame
        df = pd.DataFrame({
            'test_column': range(5)
        })
        
        # Get the bucket name from environment variables
        bucket_name = os.environ['BUCKET_NAME']
        
        # Create a buffer and save DataFrame as parquet
        buffer = BytesIO()
        df.to_parquet(buffer)
        buffer.seek(0)
        
        # Upload to S3
        s3_client = boto3.client('s3')
        key = f'test/test_data_{datetime.now().strftime("%Y%m%d_%H%M%S")}.parquet'
        
        s3_client.upload_fileobj(buffer, bucket_name, key)
        
        return {
            'statusCode': 200,
            'body': json.dumps(f'Successfully created test file: {key}')
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }