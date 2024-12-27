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
  function_name = "nytaxi_orchestrator"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_orchestrator.lambda_handler"
  runtime       = "python3.10"
  timeout       = 60
  memory_size   = 128

  s3_bucket        = aws_s3_bucket.lambda_code.id
  s3_key           = aws_s3_object.orchestrator_code.key
  source_code_hash = filebase64sha256("../dist/lambda_orchestrator.zip")

  environment {
    variables = {
      REGION                  = var.region
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
  schedule_expression = "cron(0 0 1 * ? *)" # Runs at midnight on the 1st of each month
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
  endpoint  = var.email #"your-email@example.com"
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

# Custom policy for S3 access
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

# ------------------------------
# AWS Glue Crawler
# ------------------------------
# resource "aws_glue_crawler" "bronze_crawler" {
#   database_name = aws_glue_catalog_database.nytaxi.name
#   name          = "nytaxi_bronze_crawler"
#   role          = aws_iam_role.glue_role.arn

#   s3_target {
#     path = "s3://${aws_s3_bucket.bronze.id}/nyc_taxi/"
#   }

#   schedule = "cron(0 1 1 * ? *)"
# }



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
  glue_version      = "4.0"
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
  description = "Detect new data in raw folder"
  
  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["s3.amazonaws.com"]
      eventName   = ["PutObject", "CompleteMultipartUpload"]
      requestParameters = {
        bucketName = [aws_s3_bucket.my_bucket.id]
      }
      resources = {
        ARN = ["${aws_s3_bucket.my_bucket.arn}/nyc_taxi/*"]
      }
    }
  })
}

resource "aws_s3_bucket" "cloudtrail" {
  bucket = "${var.s3bronze_nyctaxi}-cloudtrail"
}

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
# Update CloudTrail configuration
resource "aws_cloudtrail" "s3_trail" {
  name                          = "s3-event-trail"
  s3_bucket_name               = aws_s3_bucket.cloudtrail.id
  include_global_service_events = false
  
  event_selector {
    read_write_type           = "WriteOnly"
    include_management_events = true
    
    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.my_bucket.arn}/nyc_taxi/"]
    }
  }
}

# ----------------------------------
# Glue Workflow
# ---------------------------------
# Target to start Glue workflow


resource "aws_glue_workflow" "nytaxi_workflow" {
  name = "nytaxi_etl_workflow"
}
resource "aws_glue_trigger" "start_workflow" {
  name          = "start_bronze_to_silver"
  type          = "EVENT"
  workflow_name = aws_glue_workflow.nytaxi_workflow.name
  
  event_batching_condition {
    batch_size = 1
    batch_window = 900
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

# IAM Role for EventBridge to Trigger Glue Workflow
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
        Effect = "Allow"
        Action = "glue:StartWorkflowRun"
        Resource = aws_glue_workflow.nytaxi_workflow.arn
      }
    ]
  })
}
#data "aws_caller_identity" "current" {}


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
