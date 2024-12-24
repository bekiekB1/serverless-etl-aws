import os
import pytest
from datetime import datetime
import json
from freezegun import freeze_time
from unittest.mock import MagicMock, patch

from src.lambda_functions.lambda_orchestrator import get_monthly_url, lambda_handler, notify

def test_get_monthly_url():
    with freeze_time("2024-03-15"):
        url = get_monthly_url()
        assert url == "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2024-02.parquet"


def test_notify_success(mocker):
    mock_sns_client = mocker.Mock()
    mocker.patch('boto3.client', return_value=mock_sns_client)
    os.environ['NOTIFICATION_TOPIC_ARN'] = 'test-topic-arn'

    notify("Test Subject", "Test Message")
    
    mock_sns_client.publish.assert_called_once_with(
        TopicArn='test-topic-arn',
        Subject="Test Subject",
        Message="Test Message"
    )


@patch('boto3.client')
def test_notify_success_2(mock_boto3, mock_sns):
    mock_boto3.return_value = mock_sns
    notify("Test Subject", "Test Message")
    mock_sns.publish.assert_called_once_with(
        TopicArn='test-topic-arn',
        Subject="Test Subject",
        Message="Test Message"
    )

@patch('boto3.client')
def test_notify_failure(mock_boto3, mock_sns):
    mock_sns.publish.side_effect = Exception("SNS Error")
    mock_boto3.return_value = mock_sns
    notify("Test Subject", "Test Message")

@patch('boto3.client')
def test_trigger_handler_success(mock_boto3, mock_lambda, mock_sns, mock_env):
    def get_client(service):
        return mock_lambda if service == 'lambda' else mock_sns
    mock_boto3.side_effect = get_client
    
    response = lambda_handler({}, {})
    assert response['statusCode'] == 200
    assert 'Successfully processed' in json.loads(response['body'])

@patch('boto3.client')
def test_trigger_handler_failure(mock_boto3, mock_lambda, mock_sns, mock_env):
    mock_lambda.invoke.return_value['Payload'] = MagicMock(
        read=lambda: '{"statusCode": 500, "body": {"error": "Failed"}}'.encode()
    )
    def get_client(service):
        return mock_lambda if service == 'lambda' else mock_sns
    mock_boto3.side_effect = get_client
    
    response = lambda_handler({}, {})
    assert response['statusCode'] == 500