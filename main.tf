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

# Day 1: Setup Membership and assign 2 member into group
resource "aws_iam_group_membership" "dev_team" {
  name = "dev-membership"
  users = [
    aws_iam_user.senior_dev.name,
    aws_iam_user.junior_dev.name,
  ]
  group = aws_iam_group.developers.name
}

# Day 2: Create a custom IAM Policy for S3 ReadOnly access
resource "aws_iam_policy" "s3_readonly_policy" {
  name        = "S3-ReadOnly-Custom"
  description = "Provides read-only access to all S3 buckets"

  # Using 'jsonencode' is a best practice to generate JSON safely in Terraform
  policy = jsonencode({
    Version = "2012-10-17" # This is the standard policy version date required by AWS
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:Get*", # Allows downloading objects
          "s3:List*" # Allows viewing buckets
        ]
        Resource = "*" # Applies to all S3 resources
      }
    ]
  })
}

# Attach the custom policy to the "Developers" group created in Day 1
resource "aws_iam_group_policy_attachment" "dev_s3_readonly_attach" {
  group = aws_iam_group.developers.name

  # We reference the ARN (Amazon Resource Name) of the policy we just created
  policy_arn = aws_iam_policy.s3_readonly_policy.arn
}

# Day 3: Create the IAM Role with a Trust Policy for EC2
resource "aws_iam_role" "ec2_s3_readonly_role" {
  name = "EC2-S3-ReadOnly-Role"

  # The 'assume_role_policy' defines the Trust Relationship (Mối quan hệ tin cậy)
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole" # The action required to request temporary credentials
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com" # We explicitly trust the EC2 service
        }
      }
    ]
  })
}
# Attach the AWS-managed S3 ReadOnly policy to our new Role
resource "aws_iam_role_policy_attachment" "ec2_s3_readonly_attach" {
  role       = aws_iam_role.ec2_s3_readonly_role.name

  # The ARN for the standard AWS managed S3 ReadOnly policy
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}
# Create an Instance Profile to wrap the role for EC2 attachment
resource "aws_iam_instance_profile" "ec2_s3_profile" {
  name = "EC2-S3-ReadOnly-Profile"
  role = aws_iam_role.ec2_s3_readonly_role.name
}
