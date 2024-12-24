from src.lambda_functions.lambda_function import download_and_upload_to_s3, lambda_handler  # Adjust import path
import pytest
from unittest.mock import patch, MagicMock
import os

@patch('requests.get')
def test_download_upload_success(mock_requests, mocker):
    # Setup
    mock_response = MagicMock()
    mock_response.raw = MagicMock()
    mock_response.raise_for_status.return_value = None
    mock_requests.return_value = mock_response
    
    mock_s3 = mocker.Mock()
    mocker.patch('boto3.client', return_value=mock_s3)
    
    # Execute
    result = download_and_upload_to_s3("http://test-url", "test-bucket", "2024-02")
    
    # Verify
    assert 'bronze/nyc_taxi/yellow_taxi_2024-02' in result
    mock_s3.upload_fileobj.assert_called_once()

def test_processor_success(mocker):
    # Setup
    mock_download = mocker.patch('src.lambda_functions.lambda_function.download_and_upload_to_s3', return_value='test/key.parquet')
    os.environ['BUCKET_NAME'] = 'test-bucket'
    
    # Execute
    response = lambda_handler({
        'url': 'http://test-url',
        'year_month': '2024-02'
    }, {})
    
    # Verify
    assert response['statusCode'] == 200
    assert response['body']['key'] == 'test/key.parquet'

def test_processor_failure(mocker):
    # Setup
    mock_download = mocker.patch('src.lambda_functions.lambda_function.download_and_upload_to_s3', side_effect=Exception("Processing failed"))
    os.environ['BUCKET_NAME'] = 'test-bucket'
    
    # Execute
    response = lambda_handler({
        'url': 'http://test-url',
        'year_month': '2024-02'
    }, {})
    
    # Verify
    assert response['statusCode'] == 500