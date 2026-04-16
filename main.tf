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

# --- Subnets Allocation ---

# AZ 1a
resource "aws_subnet" "public_subnet_1a" {
  vpc_id                  = aws_vpc.main_vpc.id # Tham chiếu đúng tên "main_vpc" ở trên
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = { Name = "Public-Subnet-1a" }
}

resource "aws_subnet" "private_subnet_1a" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"
  tags = { Name = "Private-Subnet-1a" }
}

# AZ 1b
resource "aws_subnet" "public_subnet_1b" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags = { Name = "Public-Subnet-1b" }
}

resource "aws_subnet" "private_subnet_1b" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1b"
  tags = { Name = "Private-Subnet-1b" }
}

# Day 8:
# 1. Create the Internet Gateway (Tạo cổng Internet)
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "Aviation-Main-IGW"
  }
}

# Day 9: Create an Elastic IP for the NAT Gateway
resource "aws_eip" "nat_eip" {
  vpc = true # Note: In newer AWS provider versions, use `domain = "vpc"` instead of `vpc = true`

  # Best Practice: EIP requires the Internet Gateway to exist first
  depends_on = [aws_internet_gateway.igw]

  tags = { Name = "Aviation-NAT-EIP" }
}
# Create the NAT Gateway in the PUBLIC subnet
resource "aws_nat_gateway" "main_nat" {
  allocation_id = aws_eip.nat_eip.id

  # IMPORTANT: Place it in Public Subnet A, NOT the private subnet!
  subnet_id     = aws_subnet.public_subnet_1a.id

  tags = { Name = "Main-NAT-Gateway" }

  depends_on = [aws_internet_gateway.igw]
}

# --- PUBLIC ROUTE TABLE (Dùng cho Load Balancer) ---
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id # Đi thẳng qua cổng chính
  }
  tags = { Name = "Public-RT" }
}

# --- PRIVATE ROUTE TABLE (Dùng cho Java App/Database) ---
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main_nat.id # Đi qua cổng NAT (Receptionist)
  }
  tags = { Name = "Private-RT" }
}

# Day 13:  Tạo VPC thứ 2 cho hệ thống
resource "aws_vpc" "shared_vpc" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "Aviation-Shared-VPC" }
}

# Tạo một Route Table mặc định cho Shared VPC
resource "aws_route_table" "shared_rt" {
  vpc_id = aws_vpc.shared_vpc.id
  tags   = { Name = "Shared-Route-Table" }
}

# Khởi tạo cầu nối Peering giữa Core VPC và Shared VPC
resource "aws_vpc_peering_connection" "core_to_shared" {
  vpc_id        = aws_vpc.main_vpc.id   # Người yêu cầu (Requester) - Core VPC
  peer_vpc_id   = aws_vpc.shared_vpc.id # Người nhận (Accepter) - Shared VPC
  auto_accept   = true                  # Tự động chấp thuận

  tags = { Name = "Core-to-Shared-Peering" }
}
# 1. Chỉ đường cho Core VPC: "Muốn sang mạng 10.1.x.x thì đi qua cầu Peering"
resource "aws_route" "core_to_shared_route" {
  route_table_id            = aws_route_table.private_rt.id # Trỏ từ Private Route Table A của Core VPC
  destination_cidr_block    = aws_vpc.shared_vpc.cidr_block   # Đích đến: 10.1.0.0/16
  vpc_peering_connection_id = aws_vpc_peering_connection.core_to_shared.id
}

# 2. Chỉ đường cho Shared VPC: "Muốn gọi ngược lại mạng 10.0.x.x thì cũng đi qua cầu Peering"
resource "aws_route" "shared_to_core_route" {
  route_table_id            = aws_route_table.shared_rt.id  # Route Table của Shared VPC
  destination_cidr_block    = aws_vpc.main_vpc.cidr_block   # Đích đến: 10.0.0.0/16
  vpc_peering_connection_id = aws_vpc_peering_connection.core_to_shared.id
}