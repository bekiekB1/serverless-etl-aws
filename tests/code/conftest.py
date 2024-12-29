import pytest
import os
import logging
from unittest.mock import MagicMock

@pytest.fixture
def mock_env():
    os.environ['PROCESSOR_FUNCTION_NAME'] = 'test-processor'
    os.environ['NOTIFICATION_TOPIC_ARN'] = 'test-topic-arn'
    os.environ['BUCKET_NAME'] = 'test-bucket'

@pytest.fixture
def mock_sns():
    return MagicMock()

@pytest.fixture
def mock_lambda():
    mock = MagicMock()
    mock.invoke.return_value = {
        'StatusCode': 200,
        'Payload': MagicMock(
            read=lambda: '{"statusCode": 200, "body": {"message": "Success"}}'.encode()
        )
    }
    return mock

@pytest.fixture
def mock_s3():
    return MagicMock()

@pytest.fixture(autouse=True)
def setup_logging():
    logger = logging.getLogger()
    logger.setLevel(logging.INFO)
    return logger