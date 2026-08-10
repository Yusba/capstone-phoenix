# backend.tf
#
# IMPORTANT: fill in bucket + dynamodb_table with the outputs from
# `terraform apply` inside bootstrap/. Terraform does not let you use
# variables here — these values must be hardcoded literals.

terraform {
  backend "s3" {
    bucket         = "phoenix-capstone-tfstate-4d3f0d19"
    key            = "phoenix-capstone/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "phoenix-capstone-tf-lock"
    encrypt        = true
  }
}
