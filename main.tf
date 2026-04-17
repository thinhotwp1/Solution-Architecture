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

# 1. Lấy một AMI mặc định giả lập có sẵn trong LocalStack
data "aws_ami" "amazon_linux_mock" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# 2. Khởi tạo máy chủ gốc (Golden Source) nằm ở private_subnet_1a
resource "aws_instance" "sia_java_source" {
  ami           = data.aws_ami.amazon_linux_mock.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.private_subnet_1a.id

  # Gắn Security Group của DB/App mà bạn đã tạo ở Day 11
  vpc_security_group_ids = [aws_security_group.db_sg.id]

  tags = { Name = "SIA-Java-Master-Source" }
}

# 3. Tạo AMI (Bản chụp mẫu) từ máy chủ gốc vừa tạo
resource "aws_ami_from_instance" "sia_java_golden_ami" {
  name               = "sia-java-golden-image-v1"
  source_instance_id = aws_instance.sia_java_source.id

  # Đảm bảo máy chủ gốc phải được tạo xong thì mới chụp ảnh
  depends_on = [aws_instance.sia_java_source]

  tags = { Name = "SIA-Java-Golden-AMI" }
}

# 4. Triển khai hàng loạt (Deploy Fleet): Tạo 2 máy chủ mới từ Golden AMI
resource "aws_instance" "sia_java_clones" {
  count         = 2 # Tham số count giúp tạo N máy chủ giống nhau

  # Sử dụng ID của AMI vừa tự tạo thay vì AMI gốc của Amazon
  ami           = aws_ami_from_instance.sia_java_golden_ami.id
  instance_type = "t3.micro"

  # Rải đều 2 máy ra 2 Zone khác nhau để đảm bảo High Availability (HA)
  # Nếu count.index = 0 -> Zone A, count.index = 1 -> Zone B
  subnet_id = count.index == 0 ? aws_subnet.private_subnet_1a.id : aws_subnet.private_subnet_1b.id

  vpc_security_group_ids = [aws_security_group.db_sg.id]

  tags = {
    Name = "SIA-Java-Clone-Node-${count.index + 1}"
  }
}
