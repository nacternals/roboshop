resource "aws_instance" "this" {
  ami                         = "ami-0b4f379183e5706b9"
  instance_type               = "t2.micro"
  key_name                    = "terraform_practice_keypair"
  associate_public_ip_address = true

  tags = {
    Name = "nginx_web_server"
  }
}
