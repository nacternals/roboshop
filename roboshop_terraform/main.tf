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
    cidr_blocks = var.my_ip_cidr
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

############################
# IAM Role for EC2 (Ansible Controller/Bastion)
############################

resource "aws_iam_role" "roboshop_ec2_role" {
  name = "Roboshop_EC2_Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "Roboshop_EC2_Role"
    Project     = var.project
    Environment = var.environment
  }
}

# Instance profile (attach this to the EC2 instance that runs ansible)
resource "aws_iam_instance_profile" "roboshop_ec2_profile" {
  name = "Roboshop_EC2_Profile"
  role = aws_iam_role.roboshop_ec2_role.name
}

############################
# Policy: Inventory Read + Create EC2
############################

resource "aws_iam_policy" "roboshop_ec2_ansible_policy" {
  name        = "Roboshop_EC2_AnsibleInventory_CreateEC2"
  description = "Allows Ansible dynamic inventory (Describe) and EC2 instance creation."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # --- Dynamic inventory permissions (read-only) ---
      {
        Sid    = "InventoryReadOnly"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeTags",
          "ec2:DescribeImages",
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeRouteTables",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeKeyPairs"
        ]
        Resource = "*"
      },

      # --- Create/Manage EC2 instances ---
      {
        Sid    = "CreateAndTagInstances"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ]
        Resource = "*"
      },

      # Optional but commonly needed when running instances (depends on how you launch)
      {
        Sid    = "OptionalLifecycle"
        Effect = "Allow"
        Action = [
          "ec2:TerminateInstances",
          "ec2:StopInstances",
          "ec2:StartInstances"
        ]
        Resource = "*"
      },

      # If the instance you launch needs an IAM role/profile, you must allow PassRole.
      # Tighten Resource to specific roles later (recommended).
      {
        Sid    = "AllowPassRole"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_roboshop_policy" {
  role       = aws_iam_role.roboshop_ec2_role.name
  policy_arn = aws_iam_policy.roboshop_ec2_ansible_policy.arn
}



resource "aws_instance" "bastionHost" {
  ami                         = var.dev_bastion_ami_id
  instance_type               = var.dev_bastion_instance_type
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  associate_public_ip_address = true
  key_name                    = var.dev_bastion_key_name

  iam_instance_profile = aws_iam_instance_profile.roboshop_ec2_profile.name

  user_data = <<-EOF
              #!/bin/bash
              set -e

              echo "===== Bastion Bootstrap Started ====="

              # Update system
              dnf update -y

              # Install base tools
              dnf install -y git unzip tree

              # Install Ansible + AWS SDK
              dnf install -y ansible-core python3-boto3 python3-botocore

              # Install AWS CLI (optional but useful)
              dnf install -y awscli

              # Install AWS collections
              mkdir -p /usr/share/ansible/collections
              ansible-galaxy collection install amazon.aws:6.5.0 community.aws \
                -p /usr/share/ansible/collections

              # Create ansadmin user if not exists
              id ansadmin &>/dev/null || useradd ansadmin

              mkdir -p /home/ansadmin/.ssh
              chown -R ansadmin:ansadmin /home/ansadmin/.ssh
              chmod 700 /home/ansadmin/.ssh

              # Generate SSH key (only if not exists)
              if [ ! -f /home/ansadmin/.ssh/id_ed25519 ]; then
                sudo -u ansadmin ssh-keygen -t ed25519 -N "" \
                  -f /home/ansadmin/.ssh/id_ed25519
              fi

              chmod 600 /home/ansadmin/.ssh/id_ed25519
              chmod 644 /home/ansadmin/.ssh/id_ed25519.pub
              chown ansadmin:ansadmin /home/ansadmin/.ssh/id_ed25519*

              echo "===== Bastion Bootstrap Completed ====="
              EOF

  tags = {
    Name        = "${var.project}-${var.environment}-bastionHost"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_instance" "mongodb" {
  ami           = var.db_tier_ami_id
  instance_type = var.db_tier_instance_type
  key_name      = var.db_tier_ec2_key_name

  subnet_id              = aws_subnet.private_db[0].id
  vpc_security_group_ids = [aws_security_group.mongodb.id]

  # Private subnet + explicitly disable public IP
  associate_public_ip_address = false

  iam_instance_profile = aws_iam_instance_profile.roboshop_ec2_profile.name

  root_block_device {
    volume_size = 10
    volume_type = "gp2"
  }

  user_data = <<-EOF
              #!/bin/bash
              set -e

              # Create ansadmin (for Ansible)
              useradd ansadmin || true
              mkdir -p /home/ansadmin/.ssh
              chmod 700 /home/ansadmin/.ssh

              cat <<'KEYEOF' > /home/ansadmin/.ssh/authorized_keys
              ${var.db_tier_ansadmin_public_key}
              KEYEOF

              chmod 600 /home/ansadmin/.ssh/authorized_keys
              chown -R ansadmin:ansadmin /home/ansadmin/.ssh

              echo "ansadmin ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ansadmin
              chmod 440 /etc/sudoers.d/ansadmin
              EOF

  tags = {
    Name        = "mongodb"
    Project     = "roboshop"
    Environment = "dev"
    Tier        = "db"
    Component   = "mongodb"
  }
}

resource "aws_instance" "mysql" {
  ami           = var.db_tier_ami_id
  instance_type = var.db_tier_instance_type
  key_name      = var.db_tier_ec2_key_name

  subnet_id              = aws_subnet.private_db[0].id
  vpc_security_group_ids = [aws_security_group.mysql.id]

  # Private subnet + explicitly disable public IP
  associate_public_ip_address = false

  iam_instance_profile = aws_iam_instance_profile.roboshop_ec2_profile.name

  root_block_device {
    volume_size = 10
    volume_type = "gp2"
  }

  user_data = <<-EOF
              #!/bin/bash
              set -e

              # Create ansadmin (for Ansible)
              useradd ansadmin || true
              mkdir -p /home/ansadmin/.ssh
              chmod 700 /home/ansadmin/.ssh

              cat <<'KEYEOF' > /home/ansadmin/.ssh/authorized_keys
              ${var.db_tier_ansadmin_public_key}
              KEYEOF

              chmod 600 /home/ansadmin/.ssh/authorized_keys
              chown -R ansadmin:ansadmin /home/ansadmin/.ssh

              echo "ansadmin ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ansadmin
              chmod 440 /etc/sudoers.d/ansadmin
              EOF

  tags = {
    Name        = "mysql"
    Project     = "roboshop"
    Environment = "dev"
    Tier        = "db"
    Component   = "mysql"
  }
}

resource "aws_instance" "redis" {
  ami           = var.db_tier_ami_id
  instance_type = var.db_tier_instance_type
  key_name      = var.db_tier_ec2_key_name

  subnet_id              = aws_subnet.private_db[1].id
  vpc_security_group_ids = [aws_security_group.redis.id]

  # Private subnet + explicitly disable public IP
  associate_public_ip_address = false

  iam_instance_profile = aws_iam_instance_profile.roboshop_ec2_profile.name

  root_block_device {
    volume_size = 10
    volume_type = "gp2"
  }

  user_data = <<-EOF
              #!/bin/bash
              set -e

              # Create ansadmin (for Ansible)
              useradd ansadmin || true
              mkdir -p /home/ansadmin/.ssh
              chmod 700 /home/ansadmin/.ssh

              cat <<'KEYEOF' > /home/ansadmin/.ssh/authorized_keys
              ${var.db_tier_ansadmin_public_key}
              KEYEOF

              chmod 600 /home/ansadmin/.ssh/authorized_keys
              chown -R ansadmin:ansadmin /home/ansadmin/.ssh

              echo "ansadmin ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ansadmin
              chmod 440 /etc/sudoers.d/ansadmin
              EOF

  tags = {
    Name        = "redis"
    Project     = "roboshop"
    Environment = "dev"
    Tier        = "db"
    Component   = "redis"
  }
}


resource "aws_instance" "rabbitmq" {
  ami           = var.db_tier_ami_id
  instance_type = var.db_tier_instance_type
  key_name      = var.db_tier_ec2_key_name

  subnet_id              = aws_subnet.private_db[1].id
  vpc_security_group_ids = [aws_security_group.rabbitmq.id]

  # Private subnet + explicitly disable public IP
  associate_public_ip_address = false

  iam_instance_profile = aws_iam_instance_profile.roboshop_ec2_profile.name

  root_block_device {
    volume_size = 10
    volume_type = "gp2"
  }

  user_data = <<-EOF
              #!/bin/bash
              set -e

              # Create ansadmin (for Ansible)
              useradd ansadmin || true
              mkdir -p /home/ansadmin/.ssh
              chmod 700 /home/ansadmin/.ssh

              cat <<'KEYEOF' > /home/ansadmin/.ssh/authorized_keys
              ${var.db_tier_ansadmin_public_key}
              KEYEOF

              chmod 600 /home/ansadmin/.ssh/authorized_keys
              chown -R ansadmin:ansadmin /home/ansadmin/.ssh

              echo "ansadmin ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ansadmin
              chmod 440 /etc/sudoers.d/ansadmin
              EOF

  tags = {
    Name        = "rabbitmq"
    Project     = "roboshop"
    Environment = "dev"
    Tier        = "db"
    Component   = "rabbitmq"
  }
}

