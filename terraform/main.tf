# ----------------------------------------------------------------------------
# S3 Bucket Configuration for Bronze(Raw) data
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

# Enable EventBridge notifications for S3 bucket
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.my_bucket.id
  eventbridge = true
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

resource "aws_s3_object" "data_downloader" {
  bucket = aws_s3_bucket.lambda_code.id
  key    = "data_downloader.zip"
  source = "../dist/data_downloader.zip"
  etag   = filemd5("../dist/data_downloader.zip")
}

resource "aws_s3_object" "fetch_raw_data" {
  bucket = aws_s3_bucket.lambda_code.id
  key    = "fetch_raw_data.zip"
  source = "../dist/fetch_raw_data.zip"
  etag   = filemd5("../dist/fetch_raw_data.zip")
}

resource "aws_s3_object" "requests_layer" {
  bucket = aws_s3_bucket.lambda_code.id
  key    = "lambda_layer_requests.zip"
  source = "../dist/lambda_layer_requests.zip"
  etag   = filemd5("../dist/lambda_layer_requests.zip")
}

resource "aws_s3_object" "s3_operations" {
  bucket = aws_s3_bucket.lambda_code.id
  key    = "s3_operations.zip"
  source = "../dist/s3_operations.zip"
  etag   = filemd5("../dist/s3_operations.zip")
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
resource "aws_lambda_function" "nytaxi_data_downloader" {
  function_name = "nytaxi_data_downloader"
  role          = aws_iam_role.lambda_role.arn
  handler       = "data_downloader.lambda_handler"
  runtime       = "python3.10"
  timeout       = 300
  memory_size   = 1024

  s3_bucket        = aws_s3_bucket.lambda_code.bucket
  s3_key           = aws_s3_object.data_downloader.key
  source_code_hash = filebase64sha256("../dist/data_downloader.zip")

  layers = [
    aws_lambda_layer_version.requests_layer.arn
  ]

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.my_bucket.id
      REGION      = var.region
    }
  }
}

resource "aws_lambda_function" "nytaxi_fetch_raw_data" {
  function_name = "nytaxi_fetch_raw_data"
  role          = aws_iam_role.lambda_role.arn
  handler       = "fetch_raw_data.lambda_handler"
  runtime       = "python3.10"
  timeout       = 60
  memory_size   = 128

  s3_bucket        = aws_s3_bucket.lambda_code.id
  s3_key           = aws_s3_object.fetch_raw_data.key
  source_code_hash = filebase64sha256("../dist/fetch_raw_data.zip")

  layers = [
    aws_lambda_layer_version.requests_layer.arn
  ]

  environment {
    variables = {
      REGION                  = var.region
      PROCESSOR_FUNCTION_NAME = aws_lambda_function.nytaxi_data_downloader.function_name
      NOTIFICATION_TOPIC_ARN  = aws_sns_topic.processing_notifications.arn
      DYNAMODB_TABLE_NAME     = aws_dynamodb_table.nyc_taxi_processing.name
    }
  }
}


resource "aws_lambda_function" "s3_operations" {
  function_name = "s3_operations"
  role          = aws_iam_role.lambda_role.arn
  handler       = "s3_operations.lambda_handler"
  runtime       = "python3.10"
  timeout       = 60
  memory_size   = 128

  s3_bucket        = aws_s3_bucket.lambda_code.id
  s3_key           = aws_s3_object.s3_operations.key
  source_code_hash = filebase64sha256("../dist/s3_operations.zip")

  environment {
    variables = {
      REGION                  = var.region
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
          aws_lambda_function.nytaxi_data_downloader.arn
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
# Dynamodb: Manage Last Processed
# ------------------------------
resource "aws_dynamodb_table" "nyc_taxi_processing" {
  name           = "nyc-taxi-processing"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }
}
resource "aws_iam_role_policy" "lambda_dynamodb" {
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ]
        Resource = aws_dynamodb_table.nyc_taxi_processing.arn
      }
    ]
  })
}
# ------------------------------
# EventBridge Rule
# ------------------------------
resource "aws_cloudwatch_event_rule" "daily_taxi_check" {
  name                = "nytaxi-daily-check"
  description         = "Checks daily for new NYC Taxi data availability"
  # Run daily at midnight UTC
  schedule_expression = "cron(0 11 * * ? *)"

  tags = {
    Environment = "production"
    Service     = "nyc-taxi-processing"
  }
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.daily_taxi_check.name
  target_id = "TriggerNYTaxiOrchestrator"
  arn       = aws_lambda_function.nytaxi_fetch_raw_data.arn
}

# ------------------------------
# Lambda Permission for EventBridge
# ------------------------------
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.nytaxi_fetch_raw_data.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_taxi_check.arn
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
  endpoint  = var.email
}

# ------------------------------
# S3 Silver and gold Bucket
# ------------------------------
resource "aws_s3_bucket" "silver_bucket" {
  bucket = "${var.s3bronze_nyctaxi}-silver"
  tags   = var.s3_bucket_tags
}

resource "aws_s3_bucket" "gold_bucket" {
  bucket = "${var.s3bronze_nyctaxi}-gold"
  tags   = var.s3_bucket_tags
}

resource "aws_s3_bucket_versioning" "silver_versioning" {
  bucket = aws_s3_bucket.silver_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "gold_versioning" {
  bucket = aws_s3_bucket.gold_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# ----------------------------------
# IAM Role and Policies for glue
# ---------------------------------
resource "aws_iam_role" "glue_role" {
  name = "nytaxi_glue_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_s3_access" {
  name = "glue_s3_access"
  role = aws_iam_role.glue_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.my_bucket.arn,
          "${aws_s3_bucket.my_bucket.arn}/*",
          "${aws_s3_bucket.my_bucket.arn}/nyc_taxi/*",
          aws_s3_bucket.silver_bucket.arn,
          "${aws_s3_bucket.silver_bucket.arn}/*",
          aws_s3_bucket.gold_bucket.arn,
          "${aws_s3_bucket.gold_bucket.arn}/*",
          aws_s3_bucket.lambda_code.arn,
          "${aws_s3_bucket.lambda_code.arn}/*",
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "glue_lambda_access" {
  name = "glue_lambda_access"
  role = aws_iam_role.glue_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction",
          "lambda:GetFunction"
        ]
        Resource = [
          aws_lambda_function.s3_operations.arn,
          "${aws_lambda_function.s3_operations.arn}:*"  # For function versions and aliases
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "glue_cloudwatch_access" {
  name = "glue_cloudwatch_access"
  role = aws_iam_role.glue_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws-glue/jobs/*:*"
        ]
      }
    ]
  })
}

# Add at the top of your Terraform configuration file
data "aws_caller_identity" "current" {}
# ----------------------------------
# Brozone to Silver Jobs and Logs
# ---------------------------------
resource "aws_s3_object" "bronze_to_silver_script" {
  bucket = aws_s3_bucket.lambda_code.id
  key    = "bronze_to_silver.py"
  source = "../src/glue_scripts/bronze_to_silver.py"
  etag   = filemd5("../src/glue_scripts/bronze_to_silver.py")
}

resource "aws_glue_job" "bronze_to_silver" {
  name              = "nytaxi_bronze_to_silver"
  role_arn          = aws_iam_role.glue_role.arn
  glue_version      = "5.0"
  worker_type       = "G.1X"
  number_of_workers = 2

  command {
    script_location = "s3://${aws_s3_bucket.lambda_code.id}/bronze_to_silver.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--continuous-log-logGroup"          = "/aws-glue/jobs/bronze_to_silver"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-metrics"                   = "true"
    "--source_bucket"                    = aws_s3_bucket.my_bucket.id
    "--target_bucket"                    = aws_s3_bucket.silver_bucket.id
    "--lambda_function_name"                    = aws_lambda_function.s3_operations.function_name
  }
}

resource "aws_cloudwatch_log_group" "bronze_to_silver_logs" {
  name              = "/aws-glue/jobs/bronze_to_silver"
  retention_in_days = 30
}

# ----------------------------------
# EventBridge rule to watch S3 events
# ---------------------------------
resource "aws_cloudwatch_event_rule" "s3_trigger" {
  name        = "detect-new-taxi-data"
  description = "Detect new data in raw folder via CloudTrail"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["s3.amazonaws.com"]
      eventName   = ["PutObject", "CompleteMultipartUpload"]
      requestParameters = {
        bucketName = [aws_s3_bucket.my_bucket.id]
        key = [{
          prefix = "nyc_taxi/"
        }]
      }
    }
  })
}

# ----------------------------------
# Glue Workflow
# ---------------------------------
resource "aws_glue_workflow" "nytaxi_workflow" {
  name = "nytaxi_etl_workflow"
}

resource "aws_glue_trigger" "start_workflow" {
  name          = "start_bronze_to_silver"
  type          = "EVENT"
  workflow_name = aws_glue_workflow.nytaxi_workflow.name

  event_batching_condition {
    batch_size   = 1
    batch_window = 900  # 15 minutes to account for CloudTrail delay
  }

  actions {
    job_name = aws_glue_job.bronze_to_silver.name
    arguments = {
      "--source_path" = "s3://${aws_s3_bucket.my_bucket.id}/nyc_taxi/"
      "--target_path" = "s3://${aws_s3_bucket.silver_bucket.id}/nyc_taxi/"
    }
  }
}

resource "aws_cloudwatch_event_target" "trigger_glue_workflow" {
  rule      = aws_cloudwatch_event_rule.s3_trigger.name
  target_id = "TriggerGlueWorkflow"
  arn       = aws_glue_workflow.nytaxi_workflow.arn
  role_arn  = aws_iam_role.eventbridge_glue_role.arn
}


resource "aws_iam_role" "eventbridge_glue_role" {
  name = "eventbridge_glue_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "eventbridge_glue_policy" {
  name        = "eventbridge_glue_policy"
  description = "Policy for EventBridge to invoke Glue workflows"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "ActionsForResource",
        Effect = "Allow",
        Action = [
                "glue:notifyEvent"
            ],
        Resource = aws_glue_workflow.nytaxi_workflow.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_eventbridge_policy" {
  role       = aws_iam_role.eventbridge_glue_role.name
  policy_arn = aws_iam_policy.eventbridge_glue_policy.arn
}

# ----------------------------------
# Notification for Glue Jobs
# ---------------------------------
resource "aws_sns_topic_policy" "glue_notifications" {
  arn = aws_sns_topic.processing_notifications.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowGlueToPublish"
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.processing_notifications.arn
      }
    ]
  })
}



# CloudTrail S3 bucket for logs
resource "aws_s3_bucket" "cloudtrail" {
  bucket = "${var.s3bronze_nyctaxi}-cloudtrail"
  tags   = var.s3_bucket_tags
}

# CloudTrail bucket versioning
resource "aws_s3_bucket_versioning" "cloudtrail_versioning" {
  bucket = aws_s3_bucket.cloudtrail.id
  versioning_configuration {
    status = "Enabled"
  }
}

# CloudTrail bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_encryption" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
resource "aws_s3_bucket_public_access_block" "cloudtrail_public_access_block" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudTrail bucket policy
resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# CloudTrail configuration
resource "aws_cloudtrail" "s3_trail" {
  name                          = "s3-event-trail"
  s3_bucket_name               = aws_s3_bucket.cloudtrail.id
  include_global_service_events = false
  is_multi_region_trail        = false

  event_selector {
    read_write_type           = "WriteOnly"
    include_management_events = false

    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.my_bucket.arn}/nyc_taxi/"]
    }
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}
# Add CloudTrail bucket permissions to Glue role
resource "aws_iam_role_policy" "glue_cloudtrail_access" {
  name = "glue_cloudtrail_access"
  role = aws_iam_role.glue_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.cloudtrail.arn,
          "${aws_s3_bucket.cloudtrail.arn}/*"
        ]
      }
    ]
  })
}

# ----------------------------------------
# Optional: Secrets Manager Configuration
# ----------------------------------------
# Uncomment if needed
# resource "aws_secretsmanager_secret" "lambda_secrets" {
#   name = "nytaxi-lambda-secrets-12334674"
#   tags = var.s3_bucket_tags
# }

# resource "aws_secretsmanager_secret_version" "lambda_secrets" {
#   secret_id = aws_secretsmanager_secret.lambda_secrets.id
#   secret_string = jsonencode({
#     API_KEY = "test-api-key-123",
#     DB_PASSWORD = var.db_password,
#     ENV = "development"
#   })
# }

# resource "aws_iam_role_policy_attachment" "lambda_secrets_policy" {
#   role       = aws_iam_role.lambda_role.name
#   policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
# }
