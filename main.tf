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
  }
}

# Day 21: 1. Create the S3 Bucket
# LƯU Ý: Bạn PHẢI đổi tên bucket này thành một chuỗi ngẫu nhiên của riêng bạn - vì tên bucket là duy nhất toàn cầu.
resource "aws_s3_bucket" "sia_documents_bucket" {
  bucket = "sia-aviation-docs-2026-only-one"

  tags = {
    Name        = "SIA-Passenger-Documents"
    Environment = "Production"
  }
}

# 2. Bật tính năng Versioning (Lưu nhiều phiên bản của file - Tùy chọn nhưng Rất nên dùng)
resource "aws_s3_bucket_versioning" "sia_docs_versioning" {
  bucket = aws_s3_bucket.sia_documents_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# 3. Upload a sample object (Tạo một file mẫu trực tiếp từ Terraform)
resource "aws_s3_object" "sample_receipt" {
  bucket = aws_s3_bucket.sia_documents_bucket.id

  # Key chính là đường dẫn ẢO của file trong bucket
  key    = "receipts/2026/04/sample-booking-001.txt"

  # Nội dung file
  content = "PASSENGER: NGUYEN VAN A | FLIGHT: SQ191 | STATUS: CONFIRMED"

  # Chỉ định hạng lưu trữ (Mặc định là STANDARD nếu không ghi)
  storage_class = "STANDARD"
}