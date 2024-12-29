import boto3
from datetime import datetime
import json

class S3FileProcessor:
    def __init__(self):
        self.s3 = boto3.client('s3')
        self.cloudwatch = boto3.client('cloudwatch')
    
    def get_unprocessed_files(self, bucket, prefix):
        """Get list of unprocessed files"""
        unprocessed_files = []
        
        paginator = self.s3.get_paginator('list_objects_v2')
        for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
            if 'Contents' in page:
                for obj in page['Contents']:
                    try:
                        response = self.s3.get_object_tagging(
                            Bucket=bucket, 
                            Key=obj['Key']
                        )
                        tags = {tag['Key']: tag['Value'] for tag in response.get('TagSet', [])}
                        
                        if 'ProcessingStatus' not in tags or tags['ProcessingStatus'] != 'Processed':
                            unprocessed_files.append(obj['Key'])
                    except self.s3.exceptions.NoSuchKey:
                        continue
        
        return unprocessed_files
    
    def mark_as_processed(self, bucket, key, status='Processed', error=None):
        """Mark file with processing status"""
        tags = [
            {'Key': 'ProcessingStatus', 'Value': status},
            {'Key': 'ProcessedDate', 'Value': datetime.now().isoformat()}
        ]
        if error:
            tags.append({'Key': 'Error', 'Value': str(error)[:250]})
            
        self.s3.put_object_tagging(
            Bucket=bucket,
            Key=key,
            Tagging={'TagSet': tags}
        )
    
    def archive_file(self, bucket, key):
        """Move file to archive with date partitioning"""
        date_prefix = datetime.now().strftime('%Y/%m/%d')
        archive_key = f"archive/{date_prefix}/{key.split('/')[-1]}"
        
        self.s3.copy_object(
            Bucket=bucket,
            Key=archive_key,
            CopySource={'Bucket': bucket, 'Key': key}
        )
        self.s3.delete_object(Bucket=bucket, Key=key)

def lambda_handler(event, context):
    processor = S3FileProcessor()
    
    action = event['action']
    bucket = event['bucket']
    
    try:
        if action == 'get_unprocessed':
            prefix = event['prefix']
            files = processor.get_unprocessed_files(bucket, prefix)
            return {
                'statusCode': 200,
                'body': {'unprocessed_files': files}
            }
            
        elif action == 'mark_processed':
            key = event['key']
            status = event.get('status', 'Processed')
            error = event.get('error')
            processor.mark_as_processed(bucket, key, status, error)
            return {
                'statusCode': 200,
                'body': f'Marked {key} as {status}'
            }
            
        elif action == 'archive':
            key = event['key']
            processor.archive_file(bucket, key)
            return {
                'statusCode': 200,
                'body': f'Archived {key}'
            }
            
        else:
            return {
                'statusCode': 400,
                'body': f'Unknown action: {action}'
            }
            
    except Exception as e:
        return {
            'statusCode': 500,
            'body': str(e)
        }