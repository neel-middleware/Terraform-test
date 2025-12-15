provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public" {
  count = 2
  vpc_id = aws_vpc.main.id
  cidr_block = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  map_public_ip_on_launch = true
  availability_zone = element(["us-east-1a", "us-east-1b"], count.index)
}

resource "aws_subnet" "private" {
  count = 2
  vpc_id = aws_vpc.main.id
  cidr_block = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index + 2)
  availability_zone = element(["us-east-1a", "us-east-1b"], count.index)
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "public" {
  count = 2
  subnet_id = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "alb_sg" {
  vpc_id = aws_vpc.main.id
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "app_lb" {
  name = "app-lb"
  internal = false
  load_balancer_type = "application"
  security_groups = [aws_security_group.alb_sg.id]
  subnets = aws_subnet.public[*].id
}

resource "aws_lb_target_group" "app_tg" {
  name = "app-tg"
  port = 80
  protocol = "HTTP"
  vpc_id = aws_vpc.main.id
  health_check {
    path = "/"
    protocol = "HTTP"
  }
}

resource "aws_lb_listener" "app_listener" {
  load_balancer_arn = aws_lb.app_lb.arn
  port = 80
  protocol = "HTTP"
  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

resource "aws_launch_template" "app_lt" {
  name_prefix = "app-lt-"
  image_id = "ami-0c94855ba95c71c99" # Amazon Linux 2 AMI
  instance_type = "t3.micro"
  user_data = base64encode("#!/bin/bash\nyum install -y httpd\nsystemctl start httpd\nsystemctl enable httpd\necho 'Hello from Terraform!' > /var/www/html/index.html")
  vpc_security_group_ids = [aws_security_group.alb_sg.id]
}

resource "aws_autoscaling_group" "app_asg" {
  vpc_zone_identifier = aws_subnet.private[*].id
  desired_capacity = 2
  max_size = 4
  min_size = 2
  launch_template {
    id = aws_launch_template.app_lt.id
    version = "$Latest"
  }
  target_group_arns = [aws_lb_target_group.app_tg.arn]
  health_check_type = "EC2"
  health_check_grace_period = 300
  tag {
    key = "Name"
    value = "app-server"
    propagate_at_launch = true
  }
}
