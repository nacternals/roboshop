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
  type        = list(string)
  description = "List of allowed public IP CIDRs"
}

variable "app_port" {
  type        = number
  description = "Microservices port"
  default     = 8080
}


# EC2 (Ansible Controller / Bastion that runs Ansible dynamic inventory)
variable "dev_bastion_ami_id" {
  type        = string
  description = "AMI ID for the ansibleController/bastion instance"
}

variable "dev_bastion_instance_type" {
  type        = string
  description = "Instance type for the ansibleController/bastion instance"
  default     = "t3.micro"
}

variable "dev_bastion_key_name" {
  type        = string
  description = "Existing EC2 Key Pair name for bastion access"
}


#db tier variable details:
variable "db_tier_instance_type" {
  type        = string
  description = "db tier EC2 instance type"
}

variable "db_tier_ami_id" {
  type        = string
  description = "db tier EC2 AMI ID"
}

variable "db_tier_ec2_key_name" {
  type        = string
  description = "Existing AWS EC2 key pair name for roboshop dev environment"
}

variable "db_tier_ansadmin_public_key" {
  type        = string
  description = "roboshop dev environment bastion ansadmin public key"
}
