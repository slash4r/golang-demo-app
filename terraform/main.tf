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

  tags = {
    Name = "Public Subnet ${count.index + 1}"
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "main_igw" {
  vpc_id = aws_vpc.main_vpc.id // Attach the IGW to the VPC

  tags = {
    Name = "Main VPC IG"
  }
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

# EC2 Instances t3.micro in AZ a
resource "aws_instance" "terraform_instance_a" {
  ami           = "ami-08eb150f611ca277f"
  instance_type = "t3.micro"
  availability_zone = aws_subnet.public_subnets[0].availability_zone
  
  # Attach a network interface instead of directly assigning security groups
  network_interface {
    network_interface_id = aws_network_interface.ec2_nic.id
    device_index         = 0
  }

  user_data = <<EOF
#!/bin/bash
echo "Copying the SSH Key to the server"
echo -e "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCSdhCmNC+wp+FnQS9HR6hDCjyDN+fO/D4GGJ92rkroaes/VR7U6erT4fNlLuIqgG5E4DiKr3yWrwRpooT7w+GYPhXvybaHw6q9bq3VwfbRF+PbVkmDCXEwXZ6sN0nTJCxsCRXs8QYjj3M35e4a0J+feYmkXvcwtY9ZznT6XYqytVju2nbpbdbx9dDI84Duf0zwkiZ/Yl9l77kKAhyY3r2IX8ssILxu9YnyE5/yUdz6jc8C2FdT6xzcd0I2qVJFdw3HhMjB5tnhBi6dGiBSkYxni3oGaM0v4qn25fRdOYRyHoSMGHugjHLySz73CUc7b5G1UdhmMolGNFPRR3MMio6OaxLl5rb4f3sZSqd47rzFE41Jyk51pCqOUiMVjLkWch7dinpBzzRrRznDWxqDrfijqKJLMc4OWfLMMPTydaqb3/qhGordxDw3iwQk+ub1pnB42uqzBC18ev1wp/FcKqo+7Ww7y0fuIjEOw+5P/M3rwQu6aAgH0xALxFjKdlNGrett+AUHq3I1OwywGz+unLz1mPLKn2iddt5qShUjVokhB9yCdGlILrpQgG2IDwxdA8dz7tVOV1ES9Ji7KY/q5exaeIS8taHhZeqF5wOKeoBb6qh6gjtw5B2pT98dm+Oe7wC9wp6G9DiHG47hqnQnLIH5bGXscMd0403fLCIKzx1vgw== dennm@Kомпухтатор"
EOF

  tags = {
    Name = "Terrafom Instance A"
  }
}

# Create a network interface to manage security groups separately
resource "aws_network_interface" "ec2_nic" {
  subnet_id       = aws_subnet.public_subnets[0].id
  security_groups = [aws_security_group.allow_ssh_http.id]
  description     = "Network interface for Terraform Instance A"

  tags = {
    Name = "EC2 Network Interface"
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
  db_name              = "TerraFormDB"
  username             = "tfdbuser"
  password             = "TFDBPassword123!"

  multi_az             = false                  # Single AZ deployment
  skip_final_snapshot  = true                   # Skip final snapshot on deletion

  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  parameter_group_name = aws_db_parameter_group.rds_pg.name 
  db_subnet_group_name = aws_db_subnet_group.rds_subnet_group.name

  tags = {
    Name = "RDS Postgres DB"
  }
}
