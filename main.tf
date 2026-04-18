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

resource "aws_subnet" "public_subnet_1a" {
  vpc_id                  = aws_vpc.main_vpc.id # Tham chiếu đúng tên "main_vpc" ở trên
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = { Name = "Public-Subnet-1a" }
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
