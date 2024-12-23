variable "region" {
  description = "Region"
  default     = "us-east-2"
}

variable "s3bronze_nyctaxi" {
  description = "My S3 bucket to store raw taxi data"
  default     = "dataeng-dev-s3bronze-nyc-47893"
}

variable "s3_bucket_tags" {
  description = "Tags for the S3 bucket"
  type        = map(string)
  default = {
    Environment = "Dev"
    Creator     = "admin-user"
  }
}

# variable "db_password" {
#   description = "Database password"
#   type        = string
# }