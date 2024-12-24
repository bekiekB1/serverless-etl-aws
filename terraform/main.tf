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
resource "aws_s3_object" "orchestrator_code" {
  bucket = aws_s3_bucket.lambda_code.id
  key    = "lambda_orchestrator.zip"
  source = "../dist/lambda_orchestrator.zip"
  etag   = filemd5("../dist/lambda_orchestrator.zip")
}
resource "aws_s3_object" "requests_layer" {
  bucket = aws_s3_bucket.lambda_code.id
  key    = "lambda_layer_requests.zip"
  source = "../dist/lambda_layer_requests.zip"
  etag   = filemd5("../dist/lambda_layer_requests.zip")
}



# ----------------------------------------
# Add custom lambda layer
# ----------------------------------------
resource "aws_lambda_layer_version" "requests_layer" {
  filename            = "../dist/lambda_layer_requests.zip"
  layer_name          = "requests_layer"
  description         = "Layer for requests"
  compatible_runtimes = ["python3.10"]
}



# ------------------------------
# Lambda Function Definition
# ------------------------------
resource "aws_lambda_function" "nytaxi_loader" {
  function_name = "nytaxi_data_loader"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.10"
  timeout       = 300
  memory_size   = 1024

  s3_bucket        = aws_s3_bucket.lambda_code.id
  s3_key           = aws_s3_object.lambda_code.key
  source_code_hash = filebase64sha256("../dist/lambda_function.zip")


  layers = [
    aws_lambda_layer_version.requests_layer.arn,
    # Source: https://aws-sdk-pandas.readthedocs.io/en/stable/layers.html
    #"arn:aws:lambda:us-east-2:336392948345:layer:AWSSDKPandas-Python310:22" # hardcoded pandasSDK
  ]

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.my_bucket.id
      REGION      = var.region
    }
  }
}

resource "aws_lambda_function" "nytaxi_orchestrator" {
  function_name     = "nytaxi_orchestrator"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_orchestrator.lambda_handler"
  runtime          = "python3.10"
  timeout          = 60
  memory_size      = 128
  
  s3_bucket        = aws_s3_bucket.lambda_code.id
  s3_key           = aws_s3_object.orchestrator_code.key
  source_code_hash = filebase64sha256("../dist/lambda_orchestrator.zip")
  
  environment {
    variables = {
      REGION       = var.region
      PROCESSOR_FUNCTION_NAME = aws_lambda_function.nytaxi_loader.function_name
      NOTIFICATION_TOPIC_ARN  = aws_sns_topic.processing_notifications.arn
    }
  }
}

# ----------------------------------
# IAM Role and Policies for lambda
# ---------------------------------
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

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_invoke_policy" {
  name = "lambda_invoke_policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.nytaxi_loader.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = [
          aws_sns_topic.processing_notifications.arn
        ]
      }
    ]
  })
}



# ------------------------------
# EventBridge Rule
# ------------------------------
resource "aws_cloudwatch_event_rule" "monthly_trigger" {
  name                = "nytaxi-monthly-trigger"
  description         = "Triggers NYC Taxi data processing workflow monthly"
  schedule_expression = "cron(0 0 1 * ? *)"  # Runs at midnight on the 1st of each month
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.monthly_trigger.name
  target_id = "TriggerNYTaxiOrchestrator"
  arn       = aws_lambda_function.nytaxi_orchestrator.arn
}

# ------------------------------
# Lambda Permission for EventBridge
# ------------------------------
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.nytaxi_orchestrator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.monthly_trigger.arn
}

# ------------------------------
# SNS Topic for Notifications
# ------------------------------
resource "aws_sns_topic" "processing_notifications" {
  name = "nytaxi-processing-notifications"
}

resource "aws_sns_topic_policy" "default" {
  arn = aws_sns_topic.processing_notifications.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLambdaToPublish"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.processing_notifications.arn
      },
      {
        Sid    = "AllowLambdaRoleToPublish"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.lambda_role.arn
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.processing_notifications.arn
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.processing_notifications.arn
  protocol  = "email"
  endpoint  = var.email#"your-email@example.com"
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
