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
  s3_use_path_style           = true

  endpoints {
    iam         = "http://localstack:4566"
    sts         = "http://localstack:4566"
    ec2         = "http://localstack:4566"
    s3          = "http://localstack:4566"
    kms         = "http://localstack:4566"
    efs         = "http://localstack:4566"
  }
}

# Day 6: Khởi tạo một VPC với dải IP 10.0.x.x
resource "aws_vpc" "main_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "Aviation-Core-VPC"
  }
}

# AZ 1a
resource "aws_subnet" "private_subnet_1a" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"
  tags              = { Name = "Private-Subnet-1a" }
}

# AZ 1b
resource "aws_subnet" "private_subnet_1b" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1b"
  tags              = { Name = "Private-Subnet-1b" }
}

# 1. Create Web Security Group (For Load Balancer or Web EC2)
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
    description = "Allow traffic from Web Layer"
    from_port   = 5432 # Change to 3306 if using MySQL
    to_port     = 5432
    protocol    = "tcp"
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

# Day 24: 1. Create the EFS File System
resource "aws_efs_file_system" "sia_shared_storage" {
  creation_token   = "sia-legacy-shared-data"
  encrypted        = true # Luôn mã hóa dữ liệu at rest
  performance_mode = "generalPurpose"

  tags = { Name = "SIA-Shared-EFS" }
}

# 2. Security Group for EFS (Allow NFS traffic from EC2)
resource "aws_security_group" "efs_sg" {
  name        = "Aviation-EFS-SG"
  description = "Allow NFS traffic from Backend EC2 instances"
  vpc_id      = aws_vpc.main_vpc.id # Sử dụng VPC bạn đã tạo ở Month 1

  ingress {
    description     = "NFS from EC2"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.db_sg.id] # Chỉ cho phép EC2 thuộc SG này truy cập
  }
}

# 3. Create a Mount Target in Private Subnet 1A
resource "aws_efs_mount_target" "efs_mt_1a" {
  file_system_id  = aws_efs_file_system.sia_shared_storage.id
  subnet_id       = aws_subnet.private_subnet_1a.id
  security_groups = [aws_security_group.efs_sg.id]
}

# 4. Create a Mount Target in Private Subnet 1B (For High Availability)
resource "aws_efs_mount_target" "efs_mt_1b" {
  file_system_id  = aws_efs_file_system.sia_shared_storage.id
  subnet_id       = aws_subnet.private_subnet_1b.id
  security_groups = [aws_security_group.efs_sg.id]
}
