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

# Day 1: Tạo IAM Group "Developers" (Nhóm lập trình viên)
resource "aws_iam_group" "developers" {
  name = "Developers"
}

# Day 1: Tạo 2 IAM Users (Người dùng)
resource "aws_iam_user" "senior_dev" {
  name = "Thinh-Senior"
}

resource "aws_iam_user" "junior_dev" {
  name = "Junior-Dev"
}

# Day 1: Thiết lập Membership (Thành viên) để gán 2 user vào group
resource "aws_iam_group_membership" "dev_team" {
  name = "dev-membership"
  users = [
    aws_iam_user.senior_dev.name,
    aws_iam_user.junior_dev.name,
  ]
  group = aws_iam_group.developers.name
}
