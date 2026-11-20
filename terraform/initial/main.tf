terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "eu-west-1"
}

variable "ami_id" {
  type    = string
  default = "ami-0123456789abcdef0"
}

resource "aws_s3_bucket" "assets" {
  bucket = "northwind-assets-demo"
}

resource "aws_s3_bucket_policy" "assets" {
  bucket = aws_s3_bucket.assets.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = ["s3:GetObject"]
      Resource  = "${aws_s3_bucket.assets.arn}/*"
    }]
  })
}

resource "aws_security_group" "web" {
  name        = "web"
  description = "web tier"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
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

resource "aws_iam_policy" "deploy" {
  name = "deploy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "*"
      Resource = "*"
    }]
  })
}

resource "aws_instance" "web" {
  ami                         = var.ami_id
  instance_type               = "t3.micro"
  vpc_security_group_ids      = [aws_security_group.web.id]
  associate_public_ip_address = true
}

resource "aws_cloudwatch_log_group" "app" {
  name = "/northwind/app"
}
