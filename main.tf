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
    rds         = "http://localstack:4566"
    elasticache = "http://localstack:4566"
    dynamodb    = "http://localstack:4566"
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

# Create Web Security Group (For Load Balancer or Web EC2)
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

# Create Database Security Group (High Security)
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

# ==========================================
# Day 30 - WEEK 2 REVIEW: UNIFIED DATA TIER
# ==========================================

# 1. Unified Subnet Group for both DB and Cache
# (Tái sử dụng các Private Subnet đã tạo ở Week 1)
resource "aws_db_subnet_group" "sia_data_tier_subnets" {
  name       = "sia-data-tier-subnet-group"
  subnet_ids = [aws_subnet.private_subnet_1a.id, aws_subnet.private_subnet_1b.id]
  tags       = { Name = "SIA-Data-Tier-Subnets" }
}

resource "aws_elasticache_subnet_group" "sia_cache_subnets" {
  name       = "sia-cache-subnet-group"
  subnet_ids = [aws_subnet.private_subnet_1a.id, aws_subnet.private_subnet_1b.id]
}

# 2. The Persistent Layer: PostgreSQL RDS
resource "aws_db_instance" "sia_primary_db" {
  identifier        = "sia-core-booking-db"
  engine            = "postgres"
  engine_version    = "15.3"
  instance_class    = "db.t3.micro"
  allocated_storage = 20

  db_name  = "siabooking"
  username = "sia_admin"
  password = "SuperSecretDev2026!"

  db_subnet_group_name   = aws_db_subnet_group.sia_data_tier_subnets.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]

  multi_az            = false # Giữ false cho LocalStack/Dev để tiết kiệm tài nguyên
  publicly_accessible = false
  skip_final_snapshot = true

  tags = { Name = "SIA-Persistent-RDS" }
}

# 3. The High-Speed Layer: ElastiCache Redis
resource "aws_elasticache_cluster" "sia_flight_cache" {
  cluster_id      = "sia-flight-schedule-cache"
  engine          = "redis"
  engine_version  = "7.0"
  node_type       = "cache.t3.micro"
  num_cache_nodes = 1
  port            = 6379

  parameter_group_name = "default.redis7"
  subnet_group_name    = aws_elasticache_subnet_group.sia_cache_subnets.name

  # Sử dụng chung DB Security Group (nhớ mở thêm port 6379 trong db_sg)
  security_group_ids = [aws_security_group.db_sg.id]
}

# Day 31: Tạo bảng DynamoDB cho Nhật ký Trạng thái Chuyến bay
resource "aws_dynamodb_table" "sia_flight_status_logs" {
  name = "SIA-Flight-Status-Logs"

  # Chế độ On-Demand (Không cần đoán trước dung lượng)
  billing_mode = "PAY_PER_REQUEST"

  # Khai báo khóa chính phức hợp
  hash_key  = "FlightNumber" # Partition Key
  range_key = "UpdateTime"   # Sort Key

  # Định nghĩa kiểu dữ liệu cho các khóa (BẮT BUỘC)
  # S = String, N = Number
  attribute {
    name = "FlightNumber"
    type = "S"
  }

  attribute {
    name = "UpdateTime"
    type = "N" # Lưu Timestamp dưới dạng số (ví dụ: Epoch time)
  }

  # Lưu ý: Bạn KHÔNG CẦN khai báo các attribute khác (như Gate, Status, DelayMinutes...)
  # vì DynamoDB là NoSQL. Bạn có thể tự do chèn các trường đó vào từ code Java sau này.

  tags = {
    Name        = "SIA Flight Status Tracking"
    Environment = "Dev"
  }
}
