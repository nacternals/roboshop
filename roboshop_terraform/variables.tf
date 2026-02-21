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

variable "azs" {
  type        = list(string)
  description = "list of aws availability zones"
}

variable "public_subnet_cidrs" {
  type = list(string)
}

variable "private_nginx_subnet_cidrs" {
  type = list(string)
}

variable "private_app_subnet_cidrs" {
  type = list(string)
}

variable "private_db_subnet_cidrs" {
  type = list(string)
}

variable "my_ip_cidr" {
  type        = string
  description = "Your public IP in CIDR format, e.g., 1.2.3.4/32"
}

variable "app_port" {
  type        = number
  description = "Microservices port"
  default     = 8080
}