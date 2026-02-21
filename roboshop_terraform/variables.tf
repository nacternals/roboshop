variable "aws_region" {
  type = string
}

variable "project" {
  type        = string
  description = "Project name"
}

variable "environment" {
  type        = string
  description = "Environment name (dev/stage/prod)"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for VPC"
}
