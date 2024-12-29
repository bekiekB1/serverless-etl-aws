import json
import sys

import boto3
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from pyspark.sql.functions import *


def invoke_lambda(function_name, payload):
    """Invoke Lambda function and return response"""
    lambda_client = boto3.client("lambda")
    response = lambda_client.invoke(FunctionName=function_name, InvocationType="RequestResponse", Payload=json.dumps(payload))
    return json.loads(response["Payload"].read())


def process_taxi_data(spark, source_bucket, files_to_process):
    """Process specific taxi files"""
    if not files_to_process:
        return None

    input_paths = [f"s3://{source_bucket}/{file}" for file in files_to_process]
    df = spark.read.parquet(*input_paths)
    ## Other Tranformation Operations
    return df


def main():
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
