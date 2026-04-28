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
    sfn         = "http://localstack:4566"
  }
}

# Day 39: 1. Định nghĩa IAM Role cho Step Functions
resource "aws_iam_role" "step_functions_role" {
  name = "sia_step_functions_execution_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "states.amazonaws.com" }
    }]
  })
}

# 2. Khởi tạo Step Functions State Machine
resource "aws_sfn_state_machine" "saga_booking_workflow" {
  name     = "SIA-Saga-Booking-Workflow"
  role_arn = aws_iam_role.step_functions_role.arn

  # Định nghĩa luồng bằng Amazon States Language (ASL)
  definition = <<EOF
{
  "Comment": "A Saga pattern for Flight Booking",
  "StartAt": "ReserveFlight",
  "States": {
    "ReserveFlight": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:REGION:ACCOUNT:function:ReserveFlightLambda",
      "Next": "ProcessPayment",
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "NotifyFailure"
        }
      ]
    },
    "ProcessPayment": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:REGION:ACCOUNT:function:ProcessPaymentLambda",
      "Next": "ConfirmBooking",
      "Catch": [
        {
          "ErrorEquals": ["PaymentFailedException", "States.Timeout"],
          "Next": "CancelFlightReservation"
        }
      ]
    },
    "CancelFlightReservation": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:REGION:ACCOUNT:function:CancelFlightLambda",
      "Next": "NotifyFailure"
    },
    "ConfirmBooking": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:REGION:ACCOUNT:function:ConfirmBookingLambda",
      "End": true
    },
    "NotifyFailure": {
      "Type": "Fail",
      "Cause": "Saga Transaction Failed and Rolled Back"
    }
  }
}
EOF
}
