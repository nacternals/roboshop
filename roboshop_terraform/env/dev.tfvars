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

#############################
#App Tier Variables
#############################
app_tier_ami_id              = "ami-0b4f379183e5706b9"
app_tier_key_name            = "roboshop-dev-keypair"
app_tier_ansadmin_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE4S8UnvKKywLFjmtSI78+J71l/svBQtVsqt//iFnygC ansadmin@ip-10-10-1-125.ec2.internal"
app_services                 = ["catalogue", "user", "cart", "shipping", "payment", "dispatch"]
app_instance_type_by_service = {
  catalogue = "t2.micro"
  user      = "t2.micro"
  cart      = "t2.micro"
  shipping  = "t2.medium"
  payment   = "t2.micro"
  dispatch  = "t2.micro"
}
app_asg_min_by_service = {
  catalogue = 2
  user      = 2
  cart      = 2
  shipping  = 2
  payment   = 2
  dispatch  = 2
}

app_asg_desired_by_service = {
  catalogue = 2
  user      = 2
  cart      = 2
  shipping  = 2
  payment   = 2
  dispatch  = 2
}

app_asg_max_by_service = {
  catalogue = 4
  user      = 4
  cart      = 4
  shipping  = 4
  payment   = 4
  dispatch  = 4
}


app_health_check_path = "/health"
