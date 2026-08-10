variable "project_name" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "worker_count" {
  type = number
}

variable "subnet_id" {
  type = string
}

variable "security_group_id" {
  type = string
}

variable "public_key_path" {
  type = string
}
