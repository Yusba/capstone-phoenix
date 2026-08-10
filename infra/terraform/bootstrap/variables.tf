variable "aws_region" {
  description = "AWS region for the state bucket + lock table"
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Short name used to prefix resource names"
  type        = string
  default     = "phoenix-capstone"
}
