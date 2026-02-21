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

