output "vpc_id" {
  description = "ID of the RoboShop VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_nginx_subnet_ids" {
  value = aws_subnet.private_nginx[*].id
}

output "private_app_subnet_ids" {
  value = aws_subnet.private_app[*].id
}

output "private_db_subnet_ids" {
  value = aws_subnet.private_db[*].id
}

output "igw_id" {
  description = "Internet Gateway ID"
  value       = aws_internet_gateway.this.id
}

output "public_route_table_id" {
  value = aws_route_table.public.id
}

output "eip_ids" {
  value = aws_eip.eip[*].id
}

output "nat_gateway_ids" {
  value = aws_nat_gateway.this[*].id
}

output "rt_nginx_ids" {
  description = "NGINX private route table IDs (one per AZ)"
  value       = aws_route_table.rt_nginx[*].id
}

output "rt_app_ids" {
  description = "APP private route table IDs (one per AZ)"
  value       = aws_route_table.rt_app[*].id
}

output "rt_db_ids" {
  description = "DB private route table IDs (one per AZ)"
  value       = aws_route_table.rt_db[*].id
}

