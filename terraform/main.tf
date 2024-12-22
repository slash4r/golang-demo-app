terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region  = "eu-north-1"
}

# Create VPC
resource "aws_vpc" "main_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true

  tags = {
    Name = "main_vpc"
  }
}

# Create Public Subnets
resource "aws_subnet" "public_subnets" {
  count      = length(var.public_subnet_cidrs)
  vpc_id     = aws_vpc.main_vpc.id
  cidr_block = element(var.public_subnet_cidrs, count.index)

  availability_zone = element(var.azs, count.index)

  map_public_ip_on_launch = true

  tags = {
    Name = "TerraForm Public Subnet ${count.index + 1}"
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "main_igw" {
  vpc_id = aws_vpc.main_vpc.id // Attach the IGW to the VPC

  tags = {
    Name = "Main VPC IG"
  }
}

# Create Route Table
resource "aws_route_table" "terraform_route_table" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main_igw.id
  }

  tags = {
    Name = "Terraform Route Table"
  }
}

# Associate Route Table with Public Subnets
resource "aws_route_table_association" "public_subnet_association" {
  count          = length(aws_subnet.public_subnets)
  subnet_id      = element(aws_subnet.public_subnets[*].id, count.index)
  route_table_id = aws_route_table.terraform_route_table.id
}

# Create Security Group
resource "aws_security_group" "allow_ssh_http" {
  name        = "allow_ssh_http"
  description = "Allow SSH and HTTP inbound traffic, and all outbound traffic"
  vpc_id      = aws_vpc.main_vpc.id

  tags = {
    Name = "allow_ssh_http"
  }
}

# Inbound rule for SSH (port 22) from anywhere
resource "aws_vpc_security_group_ingress_rule" "allow_ssh" {
  security_group_id = aws_security_group.allow_ssh_http.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

# Inbound rule for HTTP (port 80) from anywhere
resource "aws_vpc_security_group_ingress_rule" "allow_http" {
  security_group_id = aws_security_group.allow_ssh_http.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

# Outbound rule allowing all traffic (IPv4)
resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.allow_ssh_http.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # Allow all traffic
}

# Outbound rule allowing all traffic (IPv6)
resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv6" {
  security_group_id = aws_security_group.allow_ssh_http.id
  cidr_ipv6         = "::/0" # Allow all traffic
  ip_protocol       = "-1" # Allow all traffic
}

# --- 1. Launch Template ---
resource "aws_launch_template" "silly_demo_launch_template" {
  name          = "silly-demo-launch-template"
  image_id      = "ami-08eb150f611ca277f"
  instance_type = "t3.micro"
  vpc_security_group_ids = [aws_security_group.allow_ssh_http.id]

  # Base64-encoded user data script for provisioning the instance
  user_data = base64encode(file("${path.module}/userdata.sh"))

  # Block device mappings (root EBS volume configuration)
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 8
      volume_type = "gp2"
    }
  }

  # Tags for instances launched from this template
  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "Silly-Demo-Instance"
    }
  }
}

# --- 2. Autoscaling Group ---
resource "aws_autoscaling_group" "silly_demo_asg" {
  desired_capacity     = 1
  max_size             = 2
  min_size             = 1
  vpc_zone_identifier  = aws_subnet.public_subnets[*].id  # Use public subnets for accessibility

  # Reference the launch template instead of a launch configuration
  launch_template {
    id      = aws_launch_template.silly_demo_launch_template.id
    version = "$Latest"
  }

  # Autoscaling group health check
  health_check_type         = "EC2"  # Can also be "ELB" if connected to a load balancer
  health_check_grace_period = 300  # 5 minutes

  # Tag each instance launched in the autoscaling group
  tag {
    key                 = "Name"
    value               = "Silly-Demo-Instance"
    propagate_at_launch = true  # Ensures tags are applied to EC2 instances created by ASG
  }
}

# Create Security Group for RDS
resource "aws_security_group" "rds_sg" {
  name        = "rds_sg"
  description = "Allow PostgreSQL traffic only from EC2"
  vpc_id      = aws_vpc.main_vpc.id

  tags = {
    Name = "RDS Security Group"
  }
}

resource "aws_security_group_rule" "rds_ingress" {
    type                     = "ingress"
    from_port                = 5432
    to_port                  = 5432
    protocol                 = "tcp"
    security_group_id        = aws_security_group.rds_sg.id
    source_security_group_id = aws_security_group.allow_ssh_http.id
}

# Create RDS Parameter Group
resource "aws_db_parameter_group" "rds_pg" {
  name        = "rds-pg-parameter-group"
  family      = "postgres13"
  description = "Custom parameter group for PostgreSQL"

  tags = {
    Name = "PostgreSQL Parameter Group"
  }
}

# Create a DB Subnet Group
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds_subnet_group"
  subnet_ids = aws_subnet.public_subnets[*].id  # the same subnets as the EC2 instances!!!

  tags = {
    Name = "RDS Subnet Group"
  }
}

#RDS PostgreSQL instance
resource "aws_db_instance" "rds_postgres" {
  allocated_storage    = 5
  apply_immediately    = true
  engine               = "postgres"
  engine_version       = "13"
  instance_class       = "db.t4g.micro"
  username             = "postgres" 
  password             = "password"

  multi_az             = false                  # Single AZ deployment
  skip_final_snapshot  = true                   # Skip final snapshot on deletion

  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  parameter_group_name = aws_db_parameter_group.rds_pg.name 
  db_subnet_group_name = aws_db_subnet_group.rds_subnet_group.name

  tags = {
    Name = "RDS Postgres DB"
  }
}

# --- 3. Application Load Balancer ---
resource "aws_lb" "app_lb" {
  name               = "app-load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_ssh_http.id]
  subnets            = aws_subnet.public_subnets[*].id

  tags = {
    Name = "Application Load Balancer"
  }
}

# --- 4. Target Group ---
resource "aws_lb_target_group" "app_lb_target_group" {
  name     = "app-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main_vpc.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"  # Expect a 200 OK response for a healthy instance
    interval            = 30     # Health check interval
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "Target Group for App"
  }
}

# --- 5. ALB Listener ---
resource "aws_lb_listener" "app_lb_listener" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_lb_target_group.arn
  }

  tags = {
    Name = "ALB Listener"
  }
}

# --- 6. Attach Target Group to Autoscaling Group ---
resource "aws_autoscaling_attachment" "asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.silly_demo_asg.name
  alb_target_group_arn   = aws_lb_target_group.app_lb_target_group.arn
}