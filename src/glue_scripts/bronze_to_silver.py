import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql.functions import *

args = getResolvedOptions(sys.argv, ['JOB_NAME', 'source_bucket', 'target_bucket'])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Read from bronze
df = spark.read.parquet(f"s3://{args['source_bucket']}/nyc_taxi/")

df_silver = df.limit(100)
# Clean and transform data
# df_silver = df.withColumn("pickup_datetime", to_timestamp("pickup_datetime")) \
#     .withColumn("dropoff_datetime", to_timestamp("dropoff_datetime")) \
#     .withColumn("pickup_date", to_date("pickup_datetime")) \
#     .withColumn("pickup_hour", hour("pickup_datetime")) \
#     .withColumn("trip_duration_minutes", 
#                 round((unix_timestamp("dropoff_datetime") - unix_timestamp("pickup_datetime")) / 60, 2)) \
#     .withColumn("distance_km", col("trip_distance") * 1.60934) \
#     .drop("store_and_fwd_flag")

# Write to silver layer partitioned by pickup_date
(
    df_silver.write
    .mode("overwrite")
    #.partitionBy("pickup_date") 
    .parquet(f"s3://{args['target_bucket']}/cleaned/")
)
job.commit()