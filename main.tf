terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    ansible = {
      source  = "ansible/ansible"
      version = "~> 1.3.0"
    }
  }
  backend "s3" {
    bucket = "murat-terra-bucket"
    key    = "terraform.tfstate"
    region = "us-east-1"
  }
}

resource "null_resource" "ansible" {
  provisioner "local-exec" {
    command = "ansible-playbook -i '${aws_instance.nginx["dev"].public_ip},' -u ec2-user --private-key ./key.pem playbook.yml"
  }

  depends_on = [aws_instance.nginx]
}




resource "aws_instance" "nginx" {
  for_each                    = local.combinations
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t2.nano"
  subnet_id                   = aws_subnet.subnet.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.sec.id]
  key_name                    = aws_key_pair.deployer.key_name

  user_data = file("user_data.sh")

  tags = {
    Name        = "instance-${local.combinations[each.key]}"
    environment = local.combinations[each.key]
    role        = local.combinations[each.key]
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*"]
  }

  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }
}

resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "main-vpc"
  }
}

resource "aws_subnet" "subnet" {
  vpc_id     = aws_vpc.vpc.id
  cidr_block = "10.0.1.0/24"

  tags = {
    Name = "Main"
  }
}

resource "aws_internet_gateway" "gateway" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "internet-gateway-for-custom-vpc"
  }
}

resource "aws_route_table" "route_table" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gateway.id
  }

  tags = {
    Name = "route_table"
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet.id
  route_table_id = aws_route_table.route_table.id
}

resource "tls_private_key" "key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_security_group" "sec" {
  name        = "allow_tls"
  description = "Allow TLS inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.vpc.id

  tags = {
    Name = "allow_tls"
  }
}

resource "aws_security_group_rule" "security" {
  type              = "ingress"
  from_port         = var.from_port
  to_port           = var.to_port
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.sec.id
}

resource "aws_security_group_rule" "egress" {
  type              = "egress"
  from_port         = var.from_port
  to_port           = var.to_port
  protocol          = "all"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.sec.id
}

resource "local_file" "cloud_pem" {
  filename = "key.pem"
  content  = tls_private_key.key.private_key_pem
}

resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = tls_private_key.key.public_key_openssh
}

locals {
  combinations = {
    dev = "dev"
  }
}

variable "from_port" {
  type    = number
  default = 0
}

variable "to_port" {
  type    = number
  default = 65535
}

