aws_region  = "us-east-1"
project     = "roboshop"
environment = "dev"

vpc_cidr                   = "10.10.0.0/16"
azs                        = ["us-east-1a", "us-east-1b"]
public_subnet_cidrs        = ["10.10.1.0/24", "10.10.2.0/24"]
private_nginx_subnet_cidrs = ["10.10.11.0/24", "10.10.12.0/24"]
private_app_subnet_cidrs   = ["10.10.21.0/24", "10.10.22.0/24"]
private_db_subnet_cidrs    = ["10.10.31.0/24", "10.10.32.0/24"]

