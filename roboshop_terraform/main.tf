resource "aws_instance" "this" {
  ami           = "ami-0b4f379183e5706b9"
  instance_type = "t2.micro"

  tags = {
    Name = "nginx_web_server"
  }
}
