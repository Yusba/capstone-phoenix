# bootstrap/main.tf
#
# Run this FIRST, before infra/terraform/main.tf.
# This creates the S3 bucket + DynamoDB table that the main config's
# remote backend depends on. It has to live outside the main config
# because Terraform can't create the backend it's about to use.
#
# Usage:
#   cd bootstrap
#   terraform init
#   terraform apply
#
# This config uses purely LOCAL state (a small terraform.tfstate file
# right here in bootstrap/). That's expected and fine — it's the one
# exception to "no local state," because this is the bucket itself.
# Do NOT commit bootstrap/terraform.tfstate to git (see .gitignore).

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Random suffix so the bucket name is globally unique without you having
# to hand-pick one (S3 bucket names are unique across ALL of AWS, not
# just your account).
resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "tf_state" {
  bucket = "${var.project_name}-tfstate-${random_id.suffix.hex}"

  # Prevent someone (or a stray `terraform destroy`) from deleting the
  # bucket that holds your state.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tf_lock" {
  name         = "${var.project_name}-tf-lock"
  billing_mode = "PAY_PER_REQUEST" # cheapest option, no idle cost
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
