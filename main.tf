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

# Day 1: Tạo IAM Group "Developers" (Nhóm lập trình viên)
resource "aws_iam_group" "developers" {
  name = "Developers"
}

# Tạo 2 IAM Users (Người dùng)
resource "aws_iam_user" "senior_dev" {
  name = "Thinh-Senior"
}

resource "aws_iam_user" "junior_dev" {
  name = "Junior-Dev"
}

# Setup Membership and assign 2 member into group
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



# --- Day 7: VPC Declaration ---
resource "aws_vpc" "main_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "Aviation-Core-VPC"
  }
}

resource "aws_subnet" "public_subnet_1a" {
  vpc_id                  = aws_vpc.main_vpc.id # Tham chiếu đúng tên "main_vpc" ở trên
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = { Name = "Public-Subnet-1a" }
}


# Day 11: 1. Create Web Security Group (For Load Balancer or Web EC2)
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

# 2. Create Database Security Group (High Security)
resource "aws_security_group" "db_sg" {
  name        = "Aviation-DB-SG"
  description = "Allow PostgreSQL traffic only from Web SG"
  vpc_id      = aws_vpc.main_vpc.id

  # Inbound Rule: Database Port
  ingress {
    description     = "Allow traffic from Web Layer"
    from_port       = 5432 # Change to 3306 if using MySQL
    to_port         = 5432
    protocol        = "tcp"
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

# Day 17: 1. Fetch the latest Amazon Linux 2023 AMI dynamically
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# 2. Create a Security Group for the Web Server
resource "aws_security_group" "nginx_sg" {
  name        = "Aviation-Nginx-SG"
  description = "Allow HTTP and SSH inbound traffic"
  vpc_id      = aws_vpc.main_vpc.id

  # Allow HTTP from anywhere (Internet)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow SSH (In production, replace 0.0.0.0/0 with your corporate VPN IP)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic (Stateless response handling)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "Nginx-Web-SG" }
}

# Day 18: 1. Create the IAM Role and Trust Policy (cho phép EC2 đóng giả Role này)
resource "aws_iam_role" "ec2_s3_readonly_role" {
  name = "Aviation-EC2-S3-ReadOnly-Role"

  # Trust Policy: Chỉ định ai được phép 'assume' (đảm nhận) role này
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# 2. Attach the AWS-managed ReadOnly policy to the Role (gắn quyền vào Role)
resource "aws_iam_role_policy_attachment" "s3_readonly_attach" {
  role       = aws_iam_role.ec2_s3_readonly_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

# 3. Create the Instance Profile (Vỏ bọc để truyền Role vào EC2)
resource "aws_iam_instance_profile" "ec2_s3_profile" {
  name = "Aviation-EC2-S3-Profile"
  role = aws_iam_role.ec2_s3_readonly_role.name
}

# 3. Launch the EC2 Instance with User Data & assign Instance Profile
resource "aws_instance" "public_web_server" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = "t3.micro"

  # Place it in the Public Subnet created on Day 7
  subnet_id     = aws_subnet.public_subnet_1a.id

  # Attach the Security Group
  vpc_security_group_ids = [aws_security_group.nginx_sg.id]

  # Assign a Public IP so we can access the Nginx welcome page
  associate_public_ip_address = true

  # Assign Instance Profile
  iam_instance_profile = aws_iam_instance_profile.ec2_s3_profile.name # DÒNG MỚI NÀY

  # The Bootstrapping Script (Runs as root on first boot)
  user_data = <<-EOF
              #!/bin/bash
              dnf update -y
              dnf install nginx -y
              systemctl start nginx
              systemctl enable nginx
              echo "<h1>SIA Aviation Public Web Server is Live!</h1>" > /usr/share/nginx/html/index.html
              EOF

  tags = {
    Name = "SIA-Public-Nginx-Server"
  }
}

# Day 19: 1. Bastion Host Security Group (The Outer Shield)
resource "aws_security_group" "bastion_sg" {
  name        = "Aviation-Bastion-SG"
  description = "Allow SSH from Corporate IP only"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    description = "SSH from Admin PC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    # BEST PRACTICE: Replace 0.0.0.0/0 with your actual Home/Office IP (e.g., "113.190.x.x/32")
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "Bastion-Security-Group" }
}

# 2. Deploy the Bastion Host in the Public Subnet
resource "aws_instance" "bastion_host" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.public_subnet_1a.id

  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  associate_public_ip_address = true # Requires a public IP to be accessible

  tags = { Name = "SIA-Bastion-Host" }
}

# 3. CRITICAL UPDATE: Modify the Private App/DB Security Group (From Day 11)
# We must update the private SG to ONLY allow SSH from the Bastion SG.
resource "aws_security_group_rule" "allow_ssh_from_bastion" {
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  security_group_id        = aws_security_group.db_sg.id # Target SG (The Private Server)
  source_security_group_id = aws_security_group.bastion_sg.id # The specific Bastion SG allowed
  description              = "Allow SSH strictly from Bastion Host"
}
