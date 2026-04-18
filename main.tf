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

# Day 22: 1. Create a Customer Managed Key (KMS Key)
resource "aws_kms_key" "sia_s3_key" {
  description             = "KMS key to encrypt SIA passenger documents"
  deletion_window_in_days = 7
  enable_key_rotation     = true # Tự động luân chuyển khóa mỗi năm (Best Practice)

  tags = { Name = "SIA-KMS-S3-Key" }
}

# Tạo một Alias (Tên gợi nhớ) cho KMS Key để dễ sử dụng
resource "aws_kms_alias" "sia_s3_key_alias" {
  name          = "alias/sia-passenger-docs-key"
  target_key_id = aws_kms_key.sia_s3_key.key_id
}

# 2. Create the Secure S3 Bucket
resource "aws_s3_bucket" "sia_secure_docs" {
  bucket = "sia-secure-passenger-data-ldt-2026"
  tags   = { Name = "SIA-Secure-Docs" }
}

# 3. Enable Versioning
resource "aws_s3_bucket_versioning" "sia_secure_versioning" {
  bucket = aws_s3_bucket.sia_secure_docs.id
  versioning_configuration {
    status = "Enabled"
  }
}

# 4. Enforce Server-Side Encryption with our KMS Key
resource "aws_s3_bucket_server_side_encryption_configuration" "sia_secure_encryption" {
  bucket = aws_s3_bucket.sia_secure_docs.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.sia_s3_key.arn
      sse_algorithm     = "aws:kms"
    }
    # Ép buộc mã hóa ngay cả khi user quên gửi header mã hóa lúc upload
    bucket_key_enabled = true
  }
}

# 5. Configure CORS (Allow a React frontend on a specific domain to upload)
resource "aws_s3_bucket_cors_configuration" "sia_secure_cors" {
  bucket = aws_s3_bucket.sia_secure_docs.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST", "GET"]
    allowed_origins = ["https://www.singaporeair.com", "http://localhost:3000"] # Chặn mọi domain khác
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}