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

# --- Subnets ---
# AZ 1a
resource "aws_subnet" "public_subnet_1a" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags                    = { Name = "Public-Subnet-1a" }
}

resource "aws_subnet" "private_subnet_1a" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"
  tags              = { Name = "Private-Subnet-1a" }
}

# AZ 1b
resource "aws_subnet" "public_subnet_1b" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags                    = { Name = "Public-Subnet-1b" }
}

resource "aws_subnet" "private_subnet_1b" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1b"
  tags              = { Name = "Private-Subnet-1b" }
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

# Day 12: 1. Create a Custom NACL for the Public Subnet
resource "aws_network_acl" "public_nacl" {
  vpc_id     = aws_vpc.main_vpc.id
  subnet_ids = [aws_subnet.public_subnet_1a.id] # Attach to Subnet 1a

  tags = { Name = "Aviation-Public-NACL" }
}

# --- INBOUND RULES (Luồng đi vào) ---

# Rule 100: Deny Hacker IP (Evaluated FIRST because number is lowest)
resource "aws_network_acl_rule" "deny_hacker_inbound" {
  network_acl_id = aws_network_acl.public_nacl.id
  rule_number    = 100
  egress         = false # false means Inbound
  protocol       = "-1"  # All protocols
  rule_action    = "deny"
  cidr_block     = "203.0.113.50/32" # Example malicious IP
}

# Rule 200: Allow HTTP from anywhere
resource "aws_network_acl_rule" "allow_http_inbound" {
  network_acl_id = aws_network_acl.public_nacl.id
  rule_number    = 200
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 80
  to_port        = 80
}

# --- OUTBOUND RULES (Luồng đi ra) ---

# Rule 100: Allow HTTP response out via Ephemeral Ports
# (Cho phép trả kết quả HTTP về qua các cổng tạm thời)
resource "aws_network_acl_rule" "allow_ephemeral_outbound" {
  network_acl_id = aws_network_acl.public_nacl.id
  rule_number    = 100
  egress         = true # true means Outbound
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535 # Ephemeral port range
}
