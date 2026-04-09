# ==========================================
# 1. 공급자 설정
# ==========================================
provider "aws" {
  region = "ap-northeast-2"
}

# ==========================================
# 2. VPC & Subnets
# ==========================================
resource "aws_vpc" "main_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "cost-zero-vpc" }
}

# 퍼블릭 서브넷 (A, C)
resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-northeast-2a"
  map_public_ip_on_launch = true
  tags = { Name = "cost-zero-public-a" }
}

resource "aws_subnet" "public_subnet_c" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "ap-northeast-2c"
  map_public_ip_on_launch = true
  tags = { Name = "cost-zero-public-c" }
}

# 프라이빗 서브넷 (A, C)
resource "aws_subnet" "private_subnet_a" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "ap-northeast-2a"
  tags = { Name = "cost-zero-private-a" }
}

resource "aws_subnet" "private_subnet_c" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.12.0/24"
  availability_zone = "ap-northeast-2c"
  tags = { Name = "cost-zero-private-c" }
}

# ==========================================
# 3. 인터넷 연결
# ==========================================
resource "aws_internet_gateway" "main_igw" {
  vpc_id = aws_vpc.main_vpc.id
  tags = { Name = "cost-zero-igw" }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main_igw.id
  }
  tags = { Name = "cost-zero-public-rt" }
}

resource "aws_route_table_association" "public_a_assoc" {
  subnet_id      = aws_subnet.public_subnet_a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_c_assoc" {
  subnet_id      = aws_subnet.public_subnet_c.id
  route_table_id = aws_route_table.public_rt.id
}

# ==========================================
# 4. 방화벽 설정 (Security Groups)
# ==========================================
# Bastion용 (외부 SSH 허용)
resource "aws_security_group" "bastion_sg" {
  name   = "bastion-sg"
  vpc_id = aws_vpc.main_vpc.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "cost-zero-bastion-sg" }
}

# Private 서버용 (VPC 내부 통신만 허용)
resource "aws_security_group" "private_sg" {
  name   = "private-sg"
  vpc_id = aws_vpc.main_vpc.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main_vpc.cidr_block]
  }
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.main_vpc.cidr_block]
  }
  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "cost-zero-private-sg" }
}

# NAT Instance용 방화벽
resource "aws_security_group" "nat_sg" {
  name   = "nat-sg"
  vpc_id = aws_vpc.main_vpc.id
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.main_vpc.cidr_block]
  }
  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "cost-zero-nat-sg" }
}

# ==========================================
# 5. 서버 생성 (EC2 Instances)
# ==========================================
data "aws_ami" "ubuntu_22_04" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# 5-1. Bastion Host (Public A)
resource "aws_instance" "bastion_host" {
  ami                    = data.aws_ami.ubuntu_22_04.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_subnet_a.id
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]
  private_ip             = "10.0.1.10"
  key_name               = "cost-zero-key" # 나중에 .tfvars 이걸로 수정

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }
  tags = { Name = "cost-zero-bastion" }
}

# 5-2. NAT Instance (Public A)
resource "aws_instance" "nat_instance" {
  ami                    = data.aws_ami.ubuntu_22_04.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_subnet_a.id
  vpc_security_group_ids = [aws_security_group.nat_sg.id]
  key_name               = "cost-zero-key" # 나중에 .tfvars 이걸로 수정
  source_dest_check      = false # NAT 필수 설정

  user_data = <<-EOF
              #!/bin/bash
              sudo sysctl -w net.ipv4.ip_forward=1
              sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
              EOF

  tags = { Name = "cost-zero-nat-instance" }
}

# 5-3. Private A
resource "aws_instance" "k3s_master" {
  ami                    = data.aws_ami.ubuntu_22_04.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private_subnet_a.id
  vpc_security_group_ids = [aws_security_group.private_sg.id]
  private_ip             = "10.0.11.10"
  key_name               = "cost-zero-key" # 나중에 .tfvars 이걸로 수정

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }
  tags = { Name = "cost-zero-k3s-master" }
}

# 5-4. Private C
resource "aws_instance" "k3s_monitor" {
  ami                    = data.aws_ami.ubuntu_22_04.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private_subnet_c.id
  vpc_security_group_ids = [aws_security_group.private_sg.id]
  private_ip             = "10.0.12.10"
  key_name               = "cost-zero-key" # 나중에 .tfvars 이걸로 수정

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }
  tags = { Name = "cost-zero-k3s-monitor" }
}

# ==========================================
# 6. 프라이빗 전용 라우팅 (NAT 연결)
# ==========================================
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main_vpc.id
  route {
    cidr_block           = "0.0.0.0/0"
    network_interface_id = aws_instance.nat_instance.primary_network_interface_id
  }
  tags = { Name = "cost-zero-private-rt" }
}

resource "aws_route_table_association" "private_a_assoc" {
  subnet_id      = aws_subnet.private_subnet_a.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "private_c_assoc" {
  subnet_id      = aws_subnet.private_subnet_c.id
  route_table_id = aws_route_table.private_rt.id
}

# ==========================================
# 7. ALB 보안 그룹
# ==========================================
resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Allow HTTP traffic to ALB"
  vpc_id      = aws_vpc.main_vpc.id

  # 외부 인터넷(0.0.0.0/0)에서 오는 웹 서비스 요청(80)을 허용합니다.
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 나가는 트래픽은 제한 없이 허용합니다.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "cost-zero-alb-sg" }
}

# ==========================================
# 8. ALB 본체 및 타겟 그룹
# ==========================================

# 3-1. ALB 생성
resource "aws_lb" "main_alb" {
  name               = "cost-zero-alb"
  internal           = false 
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  
  # 가용성을 위해 퍼블릭 서브넷 A와 C에 다리를 걸칩니다.
  subnets            = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_c.id]

  tags = { Name = "cost-zero-alb" }
}

# 3-2. 타겟 그룹 
resource "aws_lb_target_group" "k3s_tg" {
  name     = "k3s-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main_vpc.id

  # 서버의 상태를 체크
  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# 3-3. ALB 리스너 
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.k3s_tg.arn
  }
}

# 3-4. 타겟 그룹에 서버 등록
resource "aws_lb_target_group_attachment" "master_attach" {
  target_group_arn = aws_lb_target_group.k3s_tg.arn
  target_id        = aws_instance.k3s_master.id
  port             = 80
}

# ==========================================
# 9. Route 53 (도메인 연결)
# ==========================================

# 4-1. 호스팅 영역 (Hosted Zone) 생성
/*resource "aws_route53_zone" "main_zone" {
  name = "your-project-domain.com" 
}

# 4-2. ALB를 도메인에 연결 (A 레코드 Alias)
resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.main_zone.zone_id
  name    = "www"
  type    = "A"

  alias {
    name                   = aws_lb.main_alb.dns_name
    zone_id                = aws_lb.main_alb.zone_id
    evaluate_target_health = true
  }
}*/