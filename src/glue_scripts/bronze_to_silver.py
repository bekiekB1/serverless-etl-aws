import json
import sys
from typing import Any, Dict, List, Optional

import boto3
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pandas import DataFrame
from pyspark.context import SparkContext
from pyspark.sql.functions import *


def invoke_lambda(function_name: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    """Invoke Lambda function with payload
    Args:
        function_name (str): name/ARN of Lambda function to invoke
        payload (dict): data to pass to Lambda function
    Returns:
        dict: Lambda function response
    """
    lambda_client = boto3.client("lambda")
    response = lambda_client.invoke(FunctionName=function_name, InvocationType="RequestResponse", Payload=json.dumps(payload))
    return json.loads(response["Payload"].read())


def process_taxi_data(spark, source_bucket: str, files_to_process: List[str]) -> Optional[DataFrame]:
    """Process raw taxi data files into silver format
    Args:
        spark (SparkSession): active Spark session
        source_bucket (str): source S3 bucket containing raw files
        files_to_process (list): list of files to process
    Returns:
        DataFrame: processed Spark DataFrame or None if no files
    """
    if not files_to_process:
        return None

    input_paths = [f"s3://{source_bucket}/{file}" for file in files_to_process]
    df = spark.read.parquet(*input_paths)
    ## Other Tranformation Operations
    return df


def main() -> None:
    """Main Glue job function for bronze to silver transformation
    Args:
        None: reads job parameters from Glue context
    Returns:
        None: writes processed data to silver zone
    Raises:
        Exception: if processing fails
    """
    args = getResolvedOptions(sys.argv, ["JOB_NAME", "source_bucket", "target_bucket", "lambda_function_name"])

    sc = SparkContext()
    glueContext = GlueContext(sc)
    spark = glueContext.spark_session
    job = Job(glueContext)
    job.init(args["JOB_NAME"], args)

    try:
        lambda_response = invoke_lambda(
            args["lambda_function_name"], {"action": "get_unprocessed", "bucket": args["source_bucket"], "prefix": "nyc_taxi/"}
        )

        if lambda_response["statusCode"] != 200:
            raise Exception(f"Lambda error: {lambda_response['body']}")

        unprocessed_files = lambda_response["body"]["unprocessed_files"]

        if unprocessed_files:
            df_silver = process_taxi_data(spark, args["source_bucket"], unprocessed_files)

            if df_silver is not None:
                target_path = f"s3://{args['target_bucket']}/cleaned/"
                df_silver.write.mode("append").partitionBy("payment_type").parquet(target_path)

                for file_key in unprocessed_files:
                    # Mark as processed
                    invoke_lambda(args["lambda_function_name"], {"action": "mark_processed", "bucket": args["source_bucket"], "key": file_key})

                    # Archive file
                    # invoke_lambda(args['lambda_function_name'], {
                    #     'action': 'archive',
                    #     'bucket': args['source_bucket'],
                    #     'key': file_key
                    # })
        else:
            print("No new files to process")

    except Exception as e:
        print(f"Error processing data: {str(e)}")
        raise
    finally:
        job.commit()


if __name__ == "__main__":
    main()
