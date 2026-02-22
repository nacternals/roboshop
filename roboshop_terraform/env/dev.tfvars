aws_region  = "us-east-1"
project     = "roboshop"
environment = "dev"

vpc_cidr                   = "10.10.0.0/16"
azs                        = ["us-east-1a", "us-east-1b"]
public_subnet_cidrs        = ["10.10.1.0/24", "10.10.2.0/24"]
private_nginx_subnet_cidrs = ["10.10.11.0/24", "10.10.12.0/24"]
private_app_subnet_cidrs   = ["10.10.21.0/24", "10.10.22.0/24"]
private_db_subnet_cidrs    = ["10.10.31.0/24", "10.10.32.0/24"]

my_ip_cidr = ["110.235.236.116/32"]

# Controller/Bastion AMI + sizing
dev_bastion_ami_id        = "ami-0f3caa1cf4417e51b"
dev_bastion_instance_type = "t2.micro"
dev_bastion_key_name      = "roboshop-dev-keypair"

db_tier_instance_type       = "t2.medium"
db_tier_ami_id              = "ami-0b4f379183e5706b9"
db_tier_ec2_key_name        = "roboshop-dev-keypair"
db_tier_ansadmin_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE4S8UnvKKywLFjmtSI78+J71l/svBQtVsqt//iFnygC ansadmin@ip-10-10-1-125.ec2.internal"
