# --- Provider Configuration (Giữ lại để kết nối LocalStack) ---
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.65"
    }
  }
}

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    iam = "http://localstack:4566"
    sts = "http://localstack:4566"
    ec2 = "http://localstack:4566"
  }
}

# --- Day 7: VPC Declaration ---
resource "aws_vpc" "main_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "Aviation-Core-VPC"
  }
}


# Day 17: 1. Fetch the latest Amazon Linux 2023 AMI dynamically
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# 2. Create a Security Group for the Web Server
resource "aws_security_group" "nginx_sg" {
  name        = "Aviation-Nginx-SG"
  description = "Allow HTTP and SSH inbound traffic"
  vpc_id      = aws_vpc.main_vpc.id

  # Allow HTTP from anywhere (Internet)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow SSH (In production, replace 0.0.0.0/0 with your corporate VPN IP)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic (Stateless response handling)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "Nginx-Web-SG" }
}

# 3. Launch the EC2 Instance with User Data
resource "aws_instance" "public_web_server" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = "t3.micro"

  # Place it in the Public Subnet created on Day 7
  subnet_id     = aws_subnet.public_subnet_1a.id

  # Attach the Security Group
  vpc_security_group_ids = [aws_security_group.nginx_sg.id]

  # Assign a Public IP so we can access the Nginx welcome page
  associate_public_ip_address = true

  # The Bootstrapping Script (Runs as root on first boot)
  user_data = <<-EOF
              #!/bin/bash
              dnf update -y
              dnf install nginx -y
              systemctl start nginx
              systemctl enable nginx
              echo "<h1>SIA Aviation Public Web Server is Live!</h1>" > /usr/share/nginx/html/index.html
              EOF

  tags = {
    Name = "SIA-Public-Nginx-Server"
  }
}
