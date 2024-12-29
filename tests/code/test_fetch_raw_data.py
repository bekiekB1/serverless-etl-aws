from datetime import datetime
from unittest.mock import MagicMock, patch

import pytest
from moto import mock_aws

from src.lambda_functions.fetch_raw_data import (
    get_monthly_url,
    lambda_handler,
    notify,
)


def test_get_monthly_url():
    with patch("src.lambda_functions.fetch_raw_data.datetime") as mock_datetime:
        mock_datetime.now.return_value = datetime(2024, 2, 15)
        url = get_monthly_url()
        assert "2024-01" in url
        assert url.endswith(".parquet")


@mock_aws
def test_notify():
    with patch("boto3.client") as mock_boto:
        mock_sns = MagicMock()
        mock_boto.return_value = mock_sns

        with patch.dict("os.environ", {"NOTIFICATION_TOPIC_ARN": "test-arn"}):
            notify("Test Subject", "Test Message")

            mock_sns.publish.assert_called_once_with(TopicArn="test-arn", Subject="Test Subject", Message="Test Message")


@mock_aws
def test_lambda_handler():
    mock_response = {"StatusCode": 200, "Payload": MagicMock()}
    mock_response["Payload"].read.return_value = b'{"statusCode": 200}'

    with patch("boto3.client") as mock_boto, patch("src.lambda_functions.fetch_raw_data.notify") as mock_notify, patch(
        "src.lambda_functions.fetch_raw_data.get_monthly_url"
    ) as mock_url:

        mock_lambda = MagicMock()
        mock_lambda.invoke.return_value = mock_response
        mock_boto.return_value = mock_lambda
        mock_url.return_value = "http://test.com/data.parquet"

        with patch.dict("os.environ", {"PROCESSOR_FUNCTION_NAME": "test-function", "NOTIFICATION_TOPIC_ARN": "test-arn"}):
            response = lambda_handler({}, None)

            assert response["statusCode"] == 200
            mock_notify.assert_called_once()
            mock_lambda.invoke.assert_called_once()
