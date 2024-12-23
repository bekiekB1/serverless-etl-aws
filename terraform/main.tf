# ----------------------------------------------------------------------------
# S3 Bucket Configuration for Bronze(Raw) data 
#
# versioning, server-side encryption, block public access, and lifecycle rule
# ----------------------------------------------------------------------------
resource "aws_s3_bucket" "my_bucket" {
  bucket = var.s3bronze_nyctaxi
  tags   = var.s3_bucket_tags
}
resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.my_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "encryption" {
  bucket = aws_s3_bucket.my_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
resource "aws_s3_bucket_public_access_block" "public_access_block" {
  bucket                  = aws_s3_bucket.my_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_lifecycle_configuration" "bucket_lifecycle" {
  bucket = aws_s3_bucket.my_bucket.id

  rule {
    id     = "transition_and_expiration"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = 90
    }
  }
}



# ------------------------------
# IAM Role for Lambda Execution
# ------------------------------
resource "aws_iam_role" "lambda_role" {
  name = "nytaxi_lambda_admin_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "lambda_admin" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}



# ------------------------------
# Lambda Code and Configuration
# ------------------------------
resource "aws_s3_bucket" "lambda_code" {
  bucket = "${var.s3bronze_nyctaxi}-lambda-code"
  tags   = var.s3_bucket_tags
}
resource "aws_s3_bucket_versioning" "lambda_code_versioning" {
  bucket = aws_s3_bucket.lambda_code.id
  versioning_configuration {
    status = "Enabled"
  }
}
resource "aws_s3_bucket_public_access_block" "lambda_code_public_access_block" {
  bucket                  = aws_s3_bucket.lambda_code.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_object" "lambda_code" {
  bucket = aws_s3_bucket.lambda_code.id
  key    = "lambda_function.zip"
  source = "../dist/lambda_function.zip"
  etag   = filemd5("../dist/lambda_function.zip")
}


# ------------------------------
# Lambda Function Definition
# ------------------------------
# data "aws_lambda_layer_version" "pandas" {
#   layer_name = "AWSSDKPandas-Python310"
#   version    = 20
# }

resource "aws_lambda_function" "nytaxi_loader" {
  function_name     = "nytaxi_data_loader"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.10"
  timeout          = 300
  memory_size      = 1024
  
  s3_bucket        = aws_s3_bucket.lambda_code.id
  s3_key           = aws_s3_object.lambda_code.key
  source_code_hash = filebase64sha256("../dist/lambda_function.zip")

## Optional: If we want to add layers 
#   layers = [
#     #aws_lambda_layer_version.pandas_layer.arn,
#     #aws_lambda_layer_version.pyarrow_layer.arn
#      data.aws_lambda_layer_version.pandas.arn
#   ]
  layers = [
      # Source: https://aws-sdk-pandas.readthedocs.io/en/stable/layers.html
      "arn:aws:lambda:us-east-2:336392948345:layer:AWSSDKPandas-Python310:22" # hardcoded pandasSDK
      #data.aws_lambda_layer_version.pandas.arn
    ]

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.my_bucket.id
      REGION     = var.region
    }
  }
}


# ----------------------------------------
# Optional: Secrets Manager Configuration
# ----------------------------------------
# resource "aws_secretsmanager_secret" "lambda_secrets" {
#   name = "nytaxi-lambda-secrets-12334674"
#   tags = var.s3_bucket_tags
# }

# # Add example secret values
# resource "aws_secretsmanager_secret_version" "lambda_secrets" {
#   secret_id = aws_secretsmanager_secret.lambda_secrets.id
#   secret_string = jsonencode({
#     API_KEY = "test-api-key-123",
#     DB_PASSWORD = var.db_password,
#     ENV = "development"
#   })
# }

# # Update IAM role policy to allow Secrets Manager access
# resource "aws_iam_role_policy_attachment" "lambda_secrets_policy" {
#   role       = aws_iam_role.lambda_role.name
#   policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
# }



# ----------------------------------------
# Optional: Add custom lambda layer
# ----------------------------------------

# # S3 object for Lambda layer
# resource "aws_s3_object" "pandas_layer" {
#   bucket = aws_s3_bucket.lambda_code.id
#   key    = "lambda_layer_pandas.zip"
#   source = "lambda_layer_pandas.zip"
#   etag   = filemd5("lambda_layer_pandas.zip")
# }

# # S3 object for Lambda layer
# resource "aws_s3_object" "pyarrow_layer" {
#   bucket = aws_s3_bucket.lambda_code.id
#   key    = "lambda_layer_pyarrow.zip"
#   source = "lambda_layer_pyarrow.zip"
#   etag   = filemd5("lambda_layer_pyarrow.zip")
# }

# resource "aws_lambda_layer_version" "pandas_layer" {
#   filename            = "lambda_layer_pandas.zip"
#   layer_name          = "pandas_layer"
#   description         = "Layer for pandas"
#   compatible_runtimes = ["python3.10"]
# }

# resource "aws_lambda_layer_version" "pyarrow_layer" {
#   filename            = "lambda_layer_pyarrow.zip"
#   layer_name          = "pyarrow_layer"
#   description         = "Layer for pyarrow"
#   compatible_runtimes = ["python3.10"]
# }