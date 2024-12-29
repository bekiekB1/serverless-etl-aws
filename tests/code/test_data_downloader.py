from unittest.mock import MagicMock, patch

import boto3
import pytest
from botocore.exceptions import ClientError
from moto import mock_aws

from src.lambda_functions.data_downloader import (
    download_and_upload_to_s3,
    lambda_handler,
)


@pytest.fixture
def mock_env():
    with patch.dict("os.environ", {"BUCKET_NAME": "test-bucket"}):
        yield


@mock_aws
def test_download_and_upload_to_s3():
    mock_response = MagicMock()
    mock_response.raw = MagicMock()
    mock_response.raise_for_status.return_value = None

    with patch("requests.get", return_value=mock_response) as mock_get, patch("boto3.client") as mock_boto:
        mock_s3 = MagicMock()
        mock_boto.return_value = mock_s3

        result = download_and_upload_to_s3("http://test.com/data.parquet", "test-bucket", "2024-01")

        assert "nyc_taxi/yellow_taxi_2024-01_" in result
        assert result.endswith(".parquet")
        mock_get.assert_called_once()
        mock_s3.upload_fileobj.assert_called_once()


@mock_aws
def test_lambda_handler_success(mock_env):
    event = {"url": "http://test.com/data.parquet", "year_month": "2024-01"}

    with patch("src.lambda_functions.data_downloader.download_and_upload_to_s3") as mock_download:
        mock_download.return_value = "test_key"
        response = lambda_handler(event, None)

        assert response["statusCode"] == 200
        assert response["body"]["bucket"] == "test-bucket"
        assert response["body"]["key"] == "test_key"
