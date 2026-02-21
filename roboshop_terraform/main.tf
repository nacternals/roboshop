resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "${var.project}-${var.environment}-vpc"
    Project     = var.project
    Environment = var.environment
  }
}


resource "aws_subnet" "public" {
  count                   = length(var.azs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project}-${var.environment}-public-subnet-${var.azs[count.index]}"
    Project     = var.project
    Environment = var.environment
  }
}


resource "aws_subnet" "private_nginx" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_nginx_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name        = "${var.project}-${var.environment}-private-nginx-${var.azs[count.index]}"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_subnet" "private_app" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_app_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name        = "${var.project}-${var.environment}-private-app-${var.azs[count.index]}"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_subnet" "private_db" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_db_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name        = "${var.project}-${var.environment}-private-db-${var.azs[count.index]}"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name        = "${var.project}-${var.environment}-igw"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name        = "${var.project}-${var.environment}-public-rt"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_route_table_association" "public" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}


resource "aws_eip" "eip" {
  count  = length(var.azs)
  domain = "vpc"

  tags = {
    Name        = "${var.project}-${var.environment}-eip-${var.azs[count.index]}"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_nat_gateway" "this" {
  count         = length(var.azs)
  allocation_id = aws_eip.eip[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name        = "${var.project}-${var.environment}-nat-gtw-${var.azs[count.index]}"
    Project     = var.project
    Environment = var.environment
  }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "rt_nginx" {
  count  = length(var.azs)
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[count.index].id
  }

  tags = {
    Name = "${var.project}-${var.environment}-rt-nginx-${var.azs[count.index]}"
  }
}
resource "aws_route_table_association" "nginx_assoc" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.private_nginx[count.index].id
  route_table_id = aws_route_table.rt_nginx[count.index].id
}

resource "aws_route_table" "rt_app" {
  count  = length(var.azs)
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[count.index].id
  }

  tags = {
    Name = "${var.project}-${var.environment}-rt-app-${var.azs[count.index]}"
  }
}
resource "aws_route_table_association" "app_assoc" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.rt_app[count.index].id
}


resource "aws_route_table" "rt_db" {
  count  = length(var.azs)
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[count.index].id
  }

  tags = {
    Name = "${var.project}-${var.environment}-rt-db-${var.azs[count.index]}"
  }
}
resource "aws_route_table_association" "db_assoc" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.private_db[count.index].id
  route_table_id = aws_route_table.rt_db[count.index].id
}

resource "aws_security_group" "bastion" {
  name        = "${local.name_prefix}-sg-bastion"
  description = "Bastion SSH access"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${local.name_prefix}-sg-bastion"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_security_group" "alb_public" {
  name        = "${local.name_prefix}-sg-alb-public"
  description = "Public ALB access from internet"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${local.name_prefix}-sg-alb-public"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_security_group" "nginx" {
  name        = "${local.name_prefix}-sg-nginx"
  description = "Nginx instances"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "HTTP from public ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_public.id]
  }

  ingress {
    description     = "HTTPS from public ALB"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_public.id]
  }

  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${local.name_prefix}-sg-nginx"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_security_group" "alb_internal" {
  name        = "${local.name_prefix}-sg-alb-internal"
  description = "Internal ALB access from nginx"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "HTTP from nginx"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.nginx.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${local.name_prefix}-sg-alb-internal"
    Project     = var.project
    Environment = var.environment
  }
}



resource "aws_security_group" "app" {
  name        = "${local.name_prefix}-sg-app"
  description = "App tier microservices"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "App traffic from internal ALB"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_internal.id]
  }

  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${local.name_prefix}-sg-app"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_security_group" "mongodb" {
  name        = "${local.name_prefix}-sg-mongodb"
  description = "MongoDB"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "MongoDB from app"
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    description = "All outbound (optional)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${local.name_prefix}-sg-mongodb"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_security_group" "mysql" {
  name        = "${local.name_prefix}-sg-mysql"
  description = "MySQL"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "MySQL from app"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    description = "All outbound (optional)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${local.name_prefix}-sg-mysql"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_security_group" "redis" {
  name        = "${local.name_prefix}-sg-redis"
  description = "Redis"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "Redis from app"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    description = "All outbound (optional)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${local.name_prefix}-sg-redis"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_security_group" "rabbitmq" {
  name        = "${local.name_prefix}-sg-rabbitmq"
  description = "RabbitMQ"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "AMQP from app"
    from_port       = 5672
    to_port         = 5672
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  ingress {
    description     = "RabbitMQ UI from bastion (optional)"
    from_port       = 15672
    to_port         = 15672
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    description = "All outbound (optional)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${local.name_prefix}-sg-rabbitmq"
    Project     = var.project
    Environment = var.environment
  }
}

