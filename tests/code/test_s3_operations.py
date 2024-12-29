import pytest
from unittest.mock import patch, MagicMock
from src.lambda_functions.s3_operations import S3FileProcessor, lambda_handler
from moto import mock_aws

@pytest.fixture
def processor():
    return S3FileProcessor()

@mock_aws
def test_get_unprocessed_files(processor):
    mock_s3 = MagicMock()
    mock_paginator = MagicMock()
    mock_paginator.paginate.return_value = [{
        'Contents': [
            {'Key': 'file1.parquet'},
            {'Key': 'file2.parquet'}
        ]
    }]
    
    mock_s3.get_paginator.return_value = mock_paginator
    mock_s3.get_object_tagging.return_value = {'TagSet': []}
    
    processor.s3 = mock_s3
    
    files = processor.get_unprocessed_files('test-bucket', 'prefix/')
    assert len(files) == 2
    assert 'file1.parquet' in files
    assert 'file2.parquet' in files

@mock_aws
def test_mark_as_processed(processor):
    mock_s3 = MagicMock()
    processor.s3 = mock_s3
    
    processor.mark_as_processed('test-bucket', 'test-key')
    
    mock_s3.put_object_tagging.assert_called_once()
    tags = mock_s3.put_object_tagging.call_args[1]['Tagging']['TagSet']
    assert any(tag['Key'] == 'ProcessingStatus' and tag['Value'] == 'Processed' 
              for tag in tags)

@mock_aws
def test_archive_file(processor):
    mock_s3 = MagicMock()
    processor.s3 = mock_s3
    
    processor.archive_file('test-bucket', 'test-key')
    
    mock_s3.copy_object.assert_called_once()
    mock_s3.delete_object.assert_called_once()

@mock_aws
def test_lambda_handler_get_unprocessed():
    event = {
        'action': 'get_unprocessed',
        'bucket': 'test-bucket',
        'prefix': 'test/'
    }
    
    with patch('src.lambda_functions.s3_operations.S3FileProcessor') as MockProcessor:
        mock_processor = MagicMock()
        MockProcessor.return_value = mock_processor
        mock_processor.get_unprocessed_files.return_value = ['file1', 'file2']
        
        response = lambda_handler(event, None)
        
        assert response['statusCode'] == 200
        assert len(response['body']['unprocessed_files']) == 2