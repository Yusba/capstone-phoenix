variable "aws_region" {
  description = "AWS region for the cluster"
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Short name used to prefix/tag all resources"
  type        = string
  default     = "phoenix-capstone"
}

variable "instance_type" {
  description = "EC2 instance type for all nodes (control-plane + workers)"
  type        = string
  default     = "t3.micro"
}

variable "worker_count" {
  description = "Number of k3s worker (agent) nodes"
  type        = number
  default     = 2
}

variable "ssh_cidr" {
  description = "YOUR public IP in CIDR form, e.g. 41.203.x.x/32 — find it with: curl ifconfig.me. Never leave this as 0.0.0.0/0."
  type        = string
}

variable "public_key_path" {
  description = "Path to your local SSH public key, used to create the AWS key pair"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "172.31.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the single public subnet all nodes live in"
  type        = string
  default     = "172.31.1.0/24"
}
