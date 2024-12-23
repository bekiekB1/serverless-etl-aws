# Learn Event-Driven ETL Pipeline with AWS Serverless

## Project Description 
This project demonstrates how to build an event-driven ETL (Extract, Transform, Load) pipeline using AWS Serverless services. The pipeline ingests NYC Taxi data monthly, processes it through various stages (raw, transformed), and loads it into a data warehouse for analysis. 

### Key Features

* `Event-driven architecture`: Automatically trigger actions when new data arrives.
* `Serverless services`: Leverage AWS Lambda, Glue, S3, and Step Functions for a scalable, cost-effective ETL pipeline.

* `Data Lake` and `Warehouse` Integration: Organize data in S3 buckets and optionally load to Amazon Redshift for querying.

* `Infrastructure as Code (IaC)`: Use Terraform to set up resources.
Monitoring and Logging: Gain insights with CloudWatch, EventBridge, and SNS.

### Data Source:

[NYC Taxi Dataset](https://www.nyc.gov/site/tlc/about/tlc-trip-record-data.page)

### Project Structure
```bash
project-root/
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── provider.tf
│
├── src/
│   ├── lambda/
│   │   ├── lambda_function.py
│   │
│   │
│   └── layers/
│
├── scripts/
│   ├── build_lambda.py
│   └── other_scripts/
│
│
├── dist/                        # Generated files
│   ├── lambda_function.zip
│
└── pyproject.toml
```
### Milestones


**~~Setup Terraform (IaC) and Create Bronze (RAW) S3 Bucket~~**
* ~~Initialize Terraform to manage AWS resources.~~
* ~~Create a raw S3 bucket (bronze) for ingesting raw NYC taxi data.~~


**~~Create a Basic Lambda Function~~**
* ~~Write a simple AWS Lambda function to print pandas data~~

**Ingest Raw NYC Taxi Data**

* Extend the Lambda function to fetch sample NYC taxi data (100 rows for testing).
* Load the raw data into the bronze S3 bucket.

**Transform Data with AWS Glue**
* Create an AWS Glue job to process raw data from the bronze bucket.
* Load the processed data into the gold bucket.

**Orchestrate Workflow with Step Functions**
* Use AWS Step Functions to manage the ETL pipeline workflow.

**Enable Monitoring and Logging**
* Integrate AWS CloudWatch, EventBridge, and SNS for logging and notifications.

**Enhance Security with Network Isolation**
* Implement Amazon VPC for secure network configurations.

**Load to Amazon Redshift (Optional)**
* Configure data loading into Amazon Redshift (based on free tier eligibility).

**Granular Testing(Optional)**

**Implemnet CICD with github action(Optional)**

# Getting Started

## Prerequisites

**AWS Account**: Sign up for AWS Free Tier. 

**AWS IAM USER**: Create an IAM User called `admin-user` with Administrative Previlege

**Terraform**: Install Terraform for infrastructure setup.

**AWS CLI**: Configure the AWS CLI with your account credentials.

### Installing  AWS CLI
```bash
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /

# Test aws is installed
aws --version


aws configure

# ----
# Access Key ID: <From the credentials of your admin user>
# Secret Access Key: <From the credentials> (Create access key from admin-user console in security credentials tab)
# Default Region: <Your preferred region, e.g., us-east-1>
# Output Format: json (default), table, or text
# ---

# Test configuration
aws iam list-users
```

### Initialize Terraform

```bash
# add provider.tf
terraform fmt # Autoformat 
terraform init # Intialize

# Create additional variables.tf
```

### Build Aws resources with Terraform(IaC)
```bash
# Define resources, roles and access in main.tf
terraform validate
terraform plan 
terraform apply
```