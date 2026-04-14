terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.65" # Hạ version xuống 4.x để tương thích hoàn hảo với LocalStack Free
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

  # Trỏ tất cả yêu cầu IAM về LocalStack (nằm ở port 4566)
  endpoints {
    iam = "http://localstack:4566"
    sts = "http://localstack:4566"
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
# Tạo Public Subnet (Dành cho Load Balancer / API Gateway)
resource "aws_subnet" "public_subnet_1" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.1.0/24" # Cắt ra 256 IPs
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true # Tự động cấp IP Public cho máy ảo gắn vào đây

  tags = {
    Name = "Public-Subnet-1"
  }
}

# Tạo Private Subnet (Dành cho Java Backend / Database)
resource "aws_subnet" "private_subnet_1" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.2.0/24" # Cắt ra thêm 256 IPs
  availability_zone = "us-east-1a"

  tags = {
    Name = "Private-Subnet-1"
  }
}
# Create gateway to take traffic
resource "aws_internet_gateway" "main_igw" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "Main-Internet-Gateway"
  }
}
