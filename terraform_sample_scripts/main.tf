resource "aws_instance" "this" {
  ami                         = "ami-0b4f379183e5706b9"
  instance_type               = "t2.micro"
  key_name                    = "terraform_practice_keypair"
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.nginx_web_server_sg.id]

  tags = {
    Name = "nginx_web_server"
  }
}


resource "aws_security_group" "nginx_web_server_sg" {
  name        = "nginx_web_server_sg"
  description = "Allow SSH and HTTP"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]

  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
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
}
