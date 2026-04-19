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
    iam = "http://localstack:4566"
    sts = "http://localstack:4566"
    ec2 = "http://localstack:4566"
    s3  = "http://localstack:4566"
    kms = "http://localstack:4566"
  }
}

# 1. Create the EFS File System
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