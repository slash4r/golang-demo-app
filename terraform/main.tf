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

# EC2 Instances t3.micro in AZ a
resource "aws_instance" "terraform_instance_a" {
  ami           = "ami-08eb150f611ca277f"
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.public_subnets[0].id
  availability_zone = aws_subnet.public_subnets[0].availability_zone
  
  # Automatically assign a public IP - w/o Network Interface!!!
  associate_public_ip_address = true

  vpc_security_group_ids = [aws_security_group.allow_ssh_http.id]

  user_data_replace_on_change = true

  user_data =  file("${path.module}/userdata.sh")

  tags = {
    Name = "Terrafom Instance A"
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
