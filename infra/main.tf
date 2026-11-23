terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_security_group" "web" {
  name        = "jvl-web"
  description = "Acceso web y administracion"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "app" {
  ami                    = "ami-0c02fb55956c7d316"
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.web.id]

  root_block_device {
    encrypted = false
  }
}

resource "aws_s3_bucket" "logs" {
  bucket = "jvl-logs-demo"
  acl    = "public-read"
}

resource "aws_db_instance" "mysql" {
  identifier          = "jvl-db"
  engine              = "mysql"
  instance_class      = "db.t3.micro"
  allocated_storage   = 20
  username            = "admin"
  password            = "Cambiar123!"
  publicly_accessible = true
  storage_encrypted   = false
  skip_final_snapshot = true
}
