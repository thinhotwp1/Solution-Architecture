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

# Day 23: 1. Create the  S3 Bucket
resource "aws_s3_bucket" "sia_documents_bucket" {
  bucket = "sia-secure-passenger-data-ldt-2026"
  tags   = { Name = "SIA-Secure-Docs" }
}

resource "aws_s3_bucket_lifecycle_configuration" "sia_archive_policy" {
  bucket = aws_s3_bucket.sia_documents_bucket.id

  # Rule 1: Chuyển dữ liệu cũ sang Glacier
  rule {
    id     = "Archive-To-Glacier-After-30-Days"
    status = "Enabled"

    # Lọc: Áp dụng rule này cho toàn bộ bucket (bạn có thể thêm filter_prefix nếu chỉ muốn áp dụng cho 1 thư mục cụ thể)
    filter {}

    # Hành động: Chuyển đổi hạng lưu trữ
    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    # Thực hành tốt (Best Practice): Dọn dẹp luôn các bản upload bị lỗi/treo
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
