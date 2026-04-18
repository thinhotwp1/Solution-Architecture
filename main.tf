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


# Day 6: Khởi tạo một VPC với dải IP 10.0.x.x
resource "aws_vpc" "main_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "Aviation-Core-VPC"
  }
}
# Tạo Public Subnet (Dành cho Load Balancer / API Gateway)
resource "aws_subnet" "public_subnet_1" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.1.0/24" # Cắt ra 256 IPs
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true # Tự động cấp IP Public cho máy ảo gắn vào đây

  tags = {
    Name = "Public-Subnet-1"
  }
}

# Tạo Private Subnet (Dành cho Java Backend / Database)
resource "aws_subnet" "private_subnet_1" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.2.0/24" # Cắt ra thêm 256 IPs
  availability_zone = "us-east-1a"

  tags = {
    Name = "Private-Subnet-1"
  }
}
# # Create gateway to take traffic
# resource "aws_internet_gateway" "main_igw" {
#   vpc_id = aws_vpc.main_vpc.id
#
#   tags = {
#     Name = "Main-Internet-Gateway"
#   }
# }


# --- Day 6: VPC Declaration ---
resource "aws_subnet" "public_subnet_1a" {
  vpc_id                  = aws_vpc.main_vpc.id # Tham chiếu đúng tên "main_vpc" ở trên
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = { Name = "Public-Subnet-1a" }
}


# --- Day 7: Subnets Allocation ---

# AZ 1a
resource "aws_subnet" "public_subnet_1a" {
  vpc_id                  = aws_vpc.main_vpc.id # Tham chiếu đúng tên "main_vpc" ở trên
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = { Name = "Public-Subnet-1a" }
}

resource "aws_subnet" "private_subnet_1a" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"
  tags = { Name = "Private-Subnet-1a" }
}

# AZ 1b
resource "aws_subnet" "public_subnet_1b" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags = { Name = "Public-Subnet-1b" }
}

resource "aws_subnet" "private_subnet_1b" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1b"
  tags = { Name = "Private-Subnet-1b" }
}

# Day 8:
# 1. Create the Internet Gateway (Tạo cổng Internet)
resource "aws_internet_gateway" "main_igw" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "Aviation-Main-IGW"
  }
}

# 2. Create a Public Route Table (Tạo bảng định tuyến công cộng)
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    # 0.0.0.0/0 means "Anywhere" on the internet
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main_igw.id
  }

  tags = {
    Name = "Public-Route-Table"
  }
}

# 3. Associate the Route Table with Public Subnets
# (Gắn bảng định tuyến vào các Subnet công cộng)

# AZ 1a
resource "aws_route_table_association" "public_1a_assoc" {
  subnet_id      = aws_subnet.public_subnet_1a.id
  route_table_id = aws_route_table.public_rt.id
}

# AZ 1b
resource "aws_route_table_association" "public_1b_assoc" {
  subnet_id      = aws_subnet.public_subnet_1b.id
  route_table_id = aws_route_table.public_rt.id
}

# Day 9: Create an Elastic IP for the NAT Gateway
resource "aws_eip" "nat_eip" {
  vpc = true # Note: In newer AWS provider versions, use `domain = "vpc"` instead of `vpc = true`

  # Best Practice: EIP requires the Internet Gateway to exist first
  depends_on = [aws_internet_gateway.main_igw]

  tags = { Name = "Aviation-NAT-EIP" }
}
# Create the NAT Gateway in the PUBLIC subnet
resource "aws_nat_gateway" "main_nat" {
  allocation_id = aws_eip.nat_eip.id

  # IMPORTANT: Place it in Public Subnet A, NOT the private subnet!
  subnet_id     = aws_subnet.public_subnet_1a.id

  tags = { Name = "Main-NAT-Gateway" }

  depends_on = [aws_internet_gateway.main_igw]
}

# --- PUBLIC ROUTE TABLE (Dùng cho Load Balancer) ---
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main_igw.id # Đi thẳng qua cổng chính
  }
  tags = { Name = "Public-RT" }
}

# --- PRIVATE ROUTE TABLE (Dùng cho Java App/Database) ---
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main_nat.id # Đi qua cổng NAT (Receptionist)
  }
  tags = { Name = "Private-RT" }
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

# Day 12: 1. Create a Custom NACL for the Public Subnet
resource "aws_network_acl" "public_nacl" {
  vpc_id     = aws_vpc.main_vpc.id
  subnet_ids = [aws_subnet.public_subnet_1a.id] # Attach to Subnet 1a

  tags = { Name = "Aviation-Public-NACL" }
}

# --- INBOUND RULES (Luồng đi vào) ---

# Rule 100: Deny Hacker IP (Evaluated FIRST because number is lowest)
resource "aws_network_acl_rule" "deny_hacker_inbound" {
  network_acl_id = aws_network_acl.public_nacl.id
  rule_number    = 100
  egress         = false # false means Inbound
  protocol       = "-1"  # All protocols
  rule_action    = "deny"
  cidr_block     = "203.0.113.50/32" # Example malicious IP
}

# Rule 200: Allow HTTP from anywhere
resource "aws_network_acl_rule" "allow_http_inbound" {
  network_acl_id = aws_network_acl.public_nacl.id
  rule_number    = 200
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 80
  to_port        = 80
}

# --- OUTBOUND RULES (Luồng đi ra) ---

# Rule 100: Allow HTTP response out via Ephemeral Ports
# (Cho phép trả kết quả HTTP về qua các cổng tạm thời)
resource "aws_network_acl_rule" "allow_ephemeral_outbound" {
  network_acl_id = aws_network_acl.public_nacl.id
  rule_number    = 100
  egress         = true # true means Outbound
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535 # Ephemeral port range
}

# Day 13:  Tạo VPC thứ 2 cho hệ thống
resource "aws_vpc" "shared_vpc" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "Aviation-Shared-VPC" }
}

# Tạo một Route Table mặc định cho Shared VPC
resource "aws_route_table" "shared_rt" {
  vpc_id = aws_vpc.shared_vpc.id
  tags   = { Name = "Shared-Route-Table" }
}

# Khởi tạo cầu nối Peering giữa Core VPC và Shared VPC
resource "aws_vpc_peering_connection" "core_to_shared" {
  vpc_id        = aws_vpc.main_vpc.id   # Người yêu cầu (Requester) - Core VPC
  peer_vpc_id   = aws_vpc.shared_vpc.id # Người nhận (Accepter) - Shared VPC
  auto_accept   = true                  # Tự động chấp thuận

  tags = { Name = "Core-to-Shared-Peering" }
}
# 1. Chỉ đường cho Core VPC: "Muốn sang mạng 10.1.x.x thì đi qua cầu Peering"
resource "aws_route" "core_to_shared_route" {
  route_table_id            = aws_route_table.private_rt.id # Trỏ từ Private Route Table A của Core VPC
  destination_cidr_block    = aws_vpc.shared_vpc.cidr_block   # Đích đến: 10.1.0.0/16
  vpc_peering_connection_id = aws_vpc_peering_connection.core_to_shared.id
}

# 2. Chỉ đường cho Shared VPC: "Muốn gọi ngược lại mạng 10.0.x.x thì cũng đi qua cầu Peering"
resource "aws_route" "shared_to_core_route" {
  route_table_id            = aws_route_table.shared_rt.id  # Route Table của Shared VPC
  destination_cidr_block    = aws_vpc.main_vpc.cidr_block   # Đích đến: 10.0.0.0/16
  vpc_peering_connection_id = aws_vpc_peering_connection.core_to_shared.id
}

# Day 14: 1. Create the VPC Endpoint for S3 (Gateway Type)
resource "aws_vpc_endpoint" "s3_endpoint" {
  vpc_id       = aws_vpc.main_vpc.id
  service_name = "com.amazonaws.us-east-1.s3" # The official AWS service name for S3

  # Specify the type. If omitted, it defaults to Gateway, but it's best to be explicit.
  vpc_endpoint_type = "Gateway"

  tags = { Name = "Aviation-S3-Endpoint" }
}

# 2. Attach the Endpoint to your Private Route Table
# (Gắn Endpoint vào Route Table của vùng Private để chỉ đường)
resource "aws_vpc_endpoint_route_table_association" "private_s3_route" {
  route_table_id  = aws_route_table.private_rt.id # The Route table we fixed in the previous step
  vpc_endpoint_id = aws_vpc_endpoint.s3_endpoint.id
}

# 3. Optional: Endpoint Policy (Restrict access to specific buckets)
# (Chính sách bảo mật: Chỉ cho phép truy cập bucket cụ thể)
# You can add this block inside the aws_vpc_endpoint resource above.
/*
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "s3:*"
        Effect    = "Allow"
        Principal = "*"
        Resource  = [
          "arn:aws:s3:::sia-booking-receipts",
          "arn:aws:s3:::sia-booking-receipts/*"
        ]
      }
    ]
  })
*/

# Day 16: 1. Lấy một AMI mặc định giả lập có sẵn trong LocalStack
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

# 3. Launch the EC2 Instance with User Data
resource "aws_instance" "public_web_server" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = "t3.micro"

  # Place it in the Public Subnet created on Day 7
  subnet_id     = aws_subnet.public_subnet_1a.id

  # Attach the Security Group
  vpc_security_group_ids = [aws_security_group.nginx_sg.id]

  # Assign a Public IP so we can access the Nginx welcome page
  associate_public_ip_address = true

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
