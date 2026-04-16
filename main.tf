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

# Day 11: 1. Create Web Security Group (For Load Balancer or Web EC2)
resource "aws_security_group" "web_sg" {
  name        = "Aviation-Web-SG"
  description = "Allow HTTP and HTTPS inbound traffic"
  vpc_id      = aws_vpc.main_vpc.id # Attach to the VPC we built in Week 2

  # Inbound Rule 1: HTTP
  ingress {
    description = "HTTP from Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Anyone can access
  }

  # Inbound Rule 2: HTTPS
  ingress {
    description = "HTTPS from Internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound Rule: Allow everything to leave
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # "-1" means ALL protocols
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "Web-Security-Group" }
}

# 2. Create Database Security Group (High Security)
resource "aws_security_group" "db_sg" {
  name        = "Aviation-DB-SG"
  description = "Allow PostgreSQL traffic only from Web SG"
  vpc_id      = aws_vpc.main_vpc.id

  # Inbound Rule: Database Port
  ingress {
    description     = "Allow traffic from Web Layer"
    from_port       = 5432 # Change to 3306 if using MySQL
    to_port         = 5432
    protocol        = "tcp"
    # THE MAGIC HAPPENS HERE: Referencing the Web SG instead of IP
    security_groups = [aws_security_group.web_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "DB-Security-Group" }
}
