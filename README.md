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
cd terraform
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

### Configure Resources

Note: Using harcoded Pandas SDK. [ARM LINK](https://aws-sdk-pandas.readthedocs.io/en/stable/layers.html)

### **S3 Bucket Configuration:**

1. **`aws_s3_bucket.my_bucket`:**
    - Creates an S3 bucket with a name defined by the variable `var.s3bronze_nyctaxi`.
        
        **`aws_s3_bucket_versioning.versioning`:**
        
        - Enables versioning for the S3 bucket `my_bucket`.
        
        **`aws_s3_bucket_server_side_encryption_configuration.encryption`:**
        
        - Configures server-side encryption using the AES256 algorithm to encrypt objects stored in the bucket.
        
        **`aws_s3_bucket_public_access_block.public_access_block`:**
        
        - Blocks public access to the bucket by disabling public ACLs and policies.
        
        **`aws_s3_bucket_lifecycle_configuration.bucket_lifecycle`:**
        
        - Adds a lifecycle rule for the bucket to manage object transitions and expiration:
        - Moves objects to the `STANDARD_IA` (Infrequent Access) storage class after 30 days.
        - Deletes objects after 90 days.

---

### **IAM Role Configuration:**

1. **`aws_iam_role.lambda_role`:**
    - Creates an IAM role named `nytaxi_lambda_admin_role` with an assume-role policy that allows AWS Lambda to use this role.
2. **`aws_iam_role_policy_attachment.lambda_admin`:**
    - Attaches the AWS managed `AdministratorAccess` policy to the IAM role.
    - Grants full administrative permissions to the role.



### **Lambda Code Bucket Configuration:**

1. **`aws_s3_bucket.lambda_code`:**
    - Creates another S3 bucket for storing Lambda code, appending `lambda-code` to the bucket name.
    
    **`aws_s3_bucket_versioning.lambda_code_versioning`:**
    
    - Enables versioning for the Lambda code bucket.
    
    **`aws_s3_bucket_public_access_block.lambda_code_public_access_block`:**
    
    - Blocks public access for the Lambda code bucket.
    
    **`aws_s3_object.lambda_code`:**
    
    - Uploads the Lambda function code (`lambda_function.zip`) to the `lambda_code` bucket.
    - Uses the MD5 checksum to ensure the integrity of the uploaded file.

---

### **Lambda Function Configuration:**

1. **`aws_lambda_function.nytaxi_loader`:**
    - Defines a Lambda function named `nytaxi_data_loader` with the following specifications:
        - Role: Uses the IAM role `lambda_role`.
        - Handler: Specifies the entry point of the Lambda function.
        - Runtime: Uses Python 3.10.
        - Code Location: Fetches the code from the S3 bucket and key defined earlier.
        - Hashes Lambda source code: To autodetect change with hash and update the function(also includes depends_on = [aws_s3_object.lambda_code])
        - Environment Variables:
            - `BUCKET_NAME`: The ID of the `my_bucket`.
            - `REGION`: A region variable.
        - Uses `Pandas SDK layer`: "arn:aws:lambda:us-east-2:336392948345:layer:AWSSDKPandas-Python310:22"

### Test Lambda function

```bash
aws lambda invoke --function-name nytaxi_data_loader output.txt
```