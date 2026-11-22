# ---------- Networking ----------
resource "aws_vpc" "myvpc" {
  cidr_block           = var.cidr
  enable_dns_hostnames = true

  tags = {
    Name = "hamza-web-vpc"
  }
}

resource "aws_subnet" "sub1" {
  vpc_id                  = aws_vpc.myvpc.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "hamza-web-subnet-1"
  }
}

resource "aws_subnet" "sub2" {
  vpc_id                  = aws_vpc.myvpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "hamza-web-subnet-2"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.myvpc.id

  tags = {
    Name = "hamza-web-igw"
  }
}

resource "aws_route_table" "RT" {
  vpc_id = aws_vpc.myvpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "hamza-web-rt"
  }
}

resource "aws_route_table_association" "rta1" {
  subnet_id      = aws_subnet.sub1.id
  route_table_id = aws_route_table.RT.id
}

resource "aws_route_table_association" "rta2" {
  subnet_id      = aws_subnet.sub2.id
  route_table_id = aws_route_table.RT.id
}

# ---------- Security Groups ----------
# ALB: internet se sirf HTTP
resource "aws_security_group" "alb_sg" {
  name        = "hamza-web-alb-sg"
  description = "Allow HTTP from the internet to the load balancer"
  vpc_id      = aws_vpc.myvpc.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "hamza-web-alb-sg"
  }
}

# EC2: HTTP sirf ALB ke security group se
resource "aws_security_group" "web_sg" {
  name        = "hamza-web-server-sg"
  description = "Allow HTTP only from the load balancer"
  vpc_id      = aws_vpc.myvpc.id

  ingress {
    description     = "HTTP from ALB only"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "hamza-web-server-sg"
  }
}

# ---------- S3 ----------
resource "aws_s3_bucket" "example" {
  bucket = "hamza-khalid-terraform-project-2026"

  tags = {
    Name = "hamza-web-bucket"
  }
}

# ---------- AMI (latest Ubuntu 24.04) ----------
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ---------- EC2 Servers ----------
resource "aws_instance" "webserver1" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  subnet_id              = aws_subnet.sub1.id
  user_data              = file("userdata1.sh")

  depends_on = [aws_route_table_association.rta1]

  tags = {
    Name = "hamza-web-server-1"
  }
}

resource "aws_instance" "webserver2" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  subnet_id              = aws_subnet.sub2.id
  user_data              = file("userdata2.sh")

  depends_on = [aws_route_table_association.rta2]

  tags = {
    Name = "hamza-web-server-2"
  }
}

# ---------- Application Load Balancer ----------
resource "aws_lb" "myalb" {
  name               = "hamza-web-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.sub1.id, aws_subnet.sub2.id]

  depends_on = [aws_internet_gateway.igw]

  tags = {
    Name = "hamza-web-alb"
  }
}

resource "aws_lb_target_group" "tg" {
  name     = "hamza-web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.myvpc.id

  health_check {
    path = "/"
    port = "traffic-port"
  }

  tags = {
    Name = "hamza-web-tg"
  }
}

resource "aws_lb_target_group_attachment" "attach1" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.webserver1.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "attach2" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.webserver2.id
  port             = 80
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.myalb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.tg.arn
    type             = "forward"
  }
}
