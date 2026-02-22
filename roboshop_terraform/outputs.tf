############################
# Network (VPC + Subnets)
############################
output "network" {
  description = "VPC and subnet IDs"
  value = {
    vpc_id                   = aws_vpc.this.id
    vpc_cidr_block           = aws_vpc.this.cidr_block
    public_subnet_ids        = aws_subnet.public[*].id
    private_nginx_subnet_ids = aws_subnet.private_nginx[*].id
    private_app_subnet_ids   = aws_subnet.private_app[*].id
    private_db_subnet_ids    = aws_subnet.private_db[*].id
  }
}

############################
# Internet + NAT
############################
output "edge" {
  description = "Internet gateway, EIPs and NAT gateways"
  value = {
    igw_id          = aws_internet_gateway.this.id
    eip_ids         = aws_eip.eip[*].id
    nat_gateway_ids = aws_nat_gateway.this[*].id
  }
}

############################
# Route Tables
############################
output "route_tables" {
  description = "Route table IDs"
  value = {
    public_route_table_id = aws_route_table.public.id
    rt_nginx_ids          = aws_route_table.rt_nginx[*].id
    rt_app_ids            = aws_route_table.rt_app[*].id
    rt_db_ids             = aws_route_table.rt_db[*].id
  }
}

############################
# Security Groups
############################
output "sg_ids" {
  description = "Security group IDs"
  value = {
    bastion      = aws_security_group.bastion.id
    alb_public   = aws_security_group.alb_public.id
    nginx        = aws_security_group.nginx.id
    alb_internal = aws_security_group.alb_internal.id
    app          = aws_security_group.app.id
    mongodb      = aws_security_group.mongodb.id
    mysql        = aws_security_group.mysql.id
    redis        = aws_security_group.redis.id
    rabbitmq     = aws_security_group.rabbitmq.id
  }
}


############################
# Bastion
############################
output "bastion" {
  description = "Bastion instance details"
  value = {
    bastion_iam_role_name     = aws_iam_role.roboshop_ec2_role.name
    bastion_instance_id       = aws_instance.bastionHost.id
    bastion_public_ip         = aws_instance.bastionHost.public_ip
    bastion_security_group_id = aws_security_group.bastion.id
    bastion_subnet_id         = aws_subnet.public[0].id
  }
}

############################
# MongoDB Outputs
############################

output "mongodb" {
  description = "MongoDB instance details"
  value = {
    instance_id       = aws_instance.mongodb.id
    private_ip        = aws_instance.mongodb.private_ip
    availability_zone = aws_instance.mongodb.availability_zone
    subnet_id         = aws_subnet.private_db[0].id
    security_group_id = aws_security_group.mongodb.id
    iam_role_name     = aws_iam_role.roboshop_ec2_role.name
  }
}

############################
# MySQL Outputs
############################

output "mysql" {
  description = "MySQL instance details"
  value = {
    instance_id       = aws_instance.mysql.id
    private_ip        = aws_instance.mysql.private_ip
    availability_zone = aws_instance.mysql.availability_zone
    subnet_id         = aws_subnet.private_db[0].id
    security_group_id = aws_security_group.mysql.id
    iam_role_name     = aws_iam_role.roboshop_ec2_role.name
  }
}

############################
# Redis Outputs
############################

output "redis" {
  description = "Redis instance details"
  value = {
    instance_id       = aws_instance.redis.id
    private_ip        = aws_instance.redis.private_ip
    availability_zone = aws_instance.redis.availability_zone
    subnet_id         = aws_subnet.private_db[1].id
    security_group_id = aws_security_group.redis.id
    iam_role_name     = aws_iam_role.roboshop_ec2_role.name
  }
}

############################
# RabbitMQ Outputs
############################

output "rabbitmq" {
  description = "RabbitMQ instance details"
  value = {
    instance_id       = aws_instance.rabbitmq.id
    private_ip        = aws_instance.rabbitmq.private_ip
    availability_zone = aws_instance.rabbitmq.availability_zone
    subnet_id         = aws_subnet.private_db[1].id
    security_group_id = aws_security_group.rabbitmq.id
    iam_role_name     = aws_iam_role.roboshop_ec2_role.name
  }
}
