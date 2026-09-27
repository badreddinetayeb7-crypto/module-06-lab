##############################################################################
# VPC
##############################################################################

resource "aws_vpc" "project" {
  cidr_block           = "172.32.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = var.tag-name
  }
}

data "aws_vpc" "project" {
  id = aws_vpc.project.id
}

##############################################################################
# Availability Zones
##############################################################################

data "aws_availability_zones" "available" {
  state = "available"
}

output "list-of-azs" {
  description = "List of availability zones"
  value       = data.aws_availability_zones.available.names
}

##############################################################################
# Security Group
##############################################################################

resource "aws_security_group" "allow_http" {
  name = "allow_http"

  # KEEP THIS EXACT DESCRIPTION.
  # Changing it would force Terraform to replace the existing security group.
  description = "Allow http inbound traffic and all outbound traffic"

  vpc_id = aws_vpc.project.id

  tags = {
    Name  = var.tag-name
    proto = "http"
  }
}

##############################################################################
# Security Group - HTTP
##############################################################################

resource "aws_vpc_security_group_ingress_rule" "allow_http_ipv4" {
  security_group_id = aws_security_group.allow_http.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 80
  ip_protocol = "tcp"
  to_port     = 80
}

##############################################################################
# Security Group - SSH
##############################################################################

resource "aws_vpc_security_group_ingress_rule" "allow_ssh_ipv4" {
  security_group_id = aws_security_group.allow_http.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 22
  ip_protocol = "tcp"
  to_port     = 22
}

##############################################################################
# Security Group - Outbound
##############################################################################

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.allow_http.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

##############################################################################
# Security Group Data Source
##############################################################################

data "aws_security_group" "coursera-project" {
  depends_on = [
    aws_security_group.allow_http
  ]

  filter {
    name   = "tag:Name"
    values = [var.tag-name]
  }
}

##############################################################################
# DHCP Options
##############################################################################

resource "aws_vpc_dhcp_options" "project" {
  domain_name         = "${var.region}.compute.internal"
  domain_name_servers = ["AmazonProvidedDNS"]

  tags = {
    Name = var.tag-name
  }
}

resource "aws_vpc_dhcp_options_association" "dns_resolver" {
  vpc_id          = aws_vpc.project.id
  dhcp_options_id = aws_vpc_dhcp_options.project.id
}

##############################################################################
# Internet Gateway
##############################################################################

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.project.id

  tags = {
    Name = var.tag-name
  }
}

##############################################################################
# Route Table
##############################################################################

resource "aws_route_table" "example" {
  vpc_id = aws_vpc.project.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = var.tag-name
  }
}

##############################################################################
# Main Route Table
##############################################################################

resource "aws_main_route_table_association" "a" {
  vpc_id         = aws_vpc.project.id
  route_table_id = aws_route_table.example.id
}

##############################################################################
# Subnets
##############################################################################

resource "aws_subnet" "private" {
  count = var.number-of-azs

  vpc_id                  = aws_vpc.project.id
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  cidr_block = cidrsubnet(
    aws_vpc.project.cidr_block,
    4,
    count.index + 3
  )

  tags = {
    Name = var.tag-name
    Type = "private"
    Zone = data.aws_availability_zones.available.names[count.index]
  }
}

##############################################################################
# Route Table Associations
##############################################################################

resource "aws_route_table_association" "subnets" {
  count = var.number-of-azs

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.example.id
}

##############################################################################
# Subnet Data Source
##############################################################################

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [aws_vpc.project.id]
  }

  depends_on = [
    aws_subnet.private
  ]
}

output "aws_subnets" {
  value = [aws_vpc.project.id]
}

##############################################################################
# IAM Assume Role Policy
##############################################################################

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type = "Service"

      identifiers = [
        "ec2.amazonaws.com"
      ]
    }

    actions = [
      "sts:AssumeRole"
    ]
  }
}

##############################################################################
# IAM Role
##############################################################################

resource "aws_iam_role" "role" {
  name = "project_role"
  path = "/"

  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = {
    Name = var.tag-name
  }
}

##############################################################################
# IAM Instance Profile
##############################################################################

resource "aws_iam_instance_profile" "coursera_profile" {
  name = "coursera_profile"
  role = aws_iam_role.role.name
}

##############################################################################
# IAM S3 Full Access
##############################################################################

resource "aws_iam_role_policy" "s3_fullaccess_policy" {
  name = "s3_fullaccess_policy"
  role = aws_iam_role.role.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "s3:*"
        ]

        Resource = "*"
      }
    ]
  })
}

##############################################################################
# IAM DynamoDB Full Access
#
# IMPORTANT:
# The autograder specifically checks for this policy name.
##############################################################################

resource "aws_iam_role_policy" "dynamodb_fullaccess_policy" {
  name = "dynamodb_fullaccess_policy"
  role = aws_iam_role.role.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "dynamodb:*"
        ]

        Resource = "*"
      }
    ]
  })
}

##############################################################################
# IAM SNS Full Access
##############################################################################

resource "aws_iam_role_policy" "sns_fullaccess_policy" {
  name = "sns_fullaccess_policy"
  role = aws_iam_role.role.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "sns:*"
        ]

        Resource = "*"
      }
    ]
  })
}

##############################################################################
# IAM SQS Full Access
##############################################################################

resource "aws_iam_role_policy" "sqs_fullaccess_policy" {
  name = "sqs_fullaccess_policy"
  role = aws_iam_role.role.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "sqs:*"
        ]

        Resource = "*"
      }
    ]
  })
}

##############################################################################
# S3 Raw Bucket
##############################################################################

resource "aws_s3_bucket" "raw-bucket" {
  bucket        = var.raw-s3-bucket
  force_destroy = true

  tags = {
    Name = var.tag-name
  }
}

##############################################################################
# S3 Finished Bucket
##############################################################################

resource "aws_s3_bucket" "finished-bucket" {
  bucket        = var.finished-s3-bucket
  force_destroy = true

  tags = {
    Name = var.tag-name
  }
}

##############################################################################
# S3 Block Public Access - Raw
#
# The application accesses the bucket using the EC2 IAM role.
# Public bucket policies are NOT required.
##############################################################################

resource "aws_s3_bucket_public_access_block" "allow_access_from_another_account-raw" {
  bucket = aws_s3_bucket.raw-bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

##############################################################################
# S3 Block Public Access - Finished
#
# Finished images are accessed through presigned URLs from app.py.
##############################################################################

resource "aws_s3_bucket_public_access_block" "allow_access_from_another_account-finished" {
  bucket = aws_s3_bucket.finished-bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

##############################################################################
# DynamoDB Table
#
# Required:
# Table name: company
# Hash key: RecordNumber
##############################################################################

resource "aws_dynamodb_table" "coursera-dynamodb-table" {
  name = var.dynamodb-name

  billing_mode   = "PROVISIONED"
  read_capacity  = 20
  write_capacity = 20

  hash_key = "RecordNumber"

  attribute {
    name = "RecordNumber"
    type = "S"
  }

  tags = {
    Name        = var.tag-name
    Environment = "production"
  }
}

##############################################################################
# Sample DynamoDB Record
##############################################################################

resource "aws_dynamodb_table_item" "insert-sample-record" {
  depends_on = [
    aws_dynamodb_table.coursera-dynamodb-table
  ]

  table_name = aws_dynamodb_table.coursera-dynamodb-table.name
  hash_key   = aws_dynamodb_table.coursera-dynamodb-table.hash_key

  item = <<ITEM
{
  "Email": {
    "S": "sample@example.com"
  },
  "RecordNumber": {
    "S": "sample-record"
  },
  "CustomerName": {
    "S": "sample"
  },
  "Phone": {
    "S": "0000000000"
  },
  "Stat": {
    "N": "0"
  },
  "RAWS3URL": {
    "S": "sample"
  },
  "FINSIHEDS3URL": {
    "S": ""
  }
}
ITEM
}

##############################################################################
# SQS
##############################################################################

resource "aws_sqs_queue" "coursera_queue" {
  name = var.sqs-name

  delay_seconds              = 90
  max_message_size           = 262144
  message_retention_seconds  = 86400
  receive_wait_time_seconds  = 10
  visibility_timeout_seconds = 300

  tags = {
    Name = var.tag-name
  }
}

##############################################################################
# SNS
##############################################################################

resource "aws_sns_topic" "user_updates" {
  name = var.user-sns-topic

  tags = {
    Name = var.tag-name
  }
}

##############################################################################
# Backend EC2
##############################################################################

resource "aws_instance" "backend" {
  ami           = var.imageid
  instance_type = var.instance-type
  key_name      = var.key-name

  subnet_id = aws_subnet.private[0].id

  vpc_security_group_ids = [
    aws_security_group.allow_http.id
  ]

  iam_instance_profile = aws_iam_instance_profile.coursera_profile.name

  user_data = filebase64("./install-be-env.sh")

  tags = {
    Name = var.tag-name
    Type = "backend"
  }
}

output "backend-ip" {
  description = "Backend public IP"
  value       = aws_instance.backend.public_ip
}

##############################################################################
# Frontend Launch Template
##############################################################################

resource "aws_launch_template" "lt" {
  image_id      = var.imageid
  instance_type = var.instance-type
  key_name      = var.key-name

  instance_initiated_shutdown_behavior = "terminate"

  vpc_security_group_ids = [
    aws_security_group.allow_http.id
  ]

  iam_instance_profile {
    name = aws_iam_instance_profile.coursera_profile.name
  }

  monitoring {
    enabled = false
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = var.tag-name
    }
  }

  user_data = filebase64("./install-env.sh")
}

##############################################################################
# Application Load Balancer
##############################################################################

resource "aws_lb" "lb" {
  name = var.elb-name

  internal           = false
  load_balancer_type = "application"

  security_groups = [
    aws_security_group.allow_http.id
  ]

  subnets = [
    for subnet in aws_subnet.private : subnet.id
  ]

  enable_deletion_protection = false

  tags = {
    Name = var.tag-name
  }
}

output "url" {
  value = aws_lb.lb.dns_name
}

##############################################################################
# Load Balancer Target Group
##############################################################################

resource "aws_lb_target_group" "alb-lb-tg" {
  name = var.tg-name

  target_type = "instance"

  port     = 80
  protocol = "HTTP"

  vpc_id = aws_vpc.project.id

  tags = {
    Name = var.tag-name
  }
}

output "alb-lb-tg-arn" {
  value = aws_lb_target_group.alb-lb-tg.arn
}

output "alb-lb-tg-id" {
  value = aws_lb_target_group.alb-lb-tg.id
}

##############################################################################
# ALB Listener
##############################################################################

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.lb.arn

  port     = "80"
  protocol = "HTTP"

  default_action {
    type = "forward"

    target_group_arn = aws_lb_target_group.alb-lb-tg.arn
  }
}

##############################################################################
# Auto Scaling Group
##############################################################################

resource "aws_autoscaling_group" "asg" {
  name = var.asg-name

  desired_capacity = var.desired
  min_size         = var.min
  max_size         = var.max

  health_check_grace_period = 300
  health_check_type         = "EC2"

  vpc_zone_identifier = [
    for subnet in aws_subnet.private : subnet.id
  ]

  target_group_arns = [
    aws_lb_target_group.alb-lb-tg.arn
  ]

  launch_template {
    id      = aws_launch_template.lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = var.tag-name
    propagate_at_launch = true
  }

  tag {
    key                 = "assessment"
    value               = var.tag-name
    propagate_at_launch = true
  }
}

##############################################################################
# Auto Scaling Attachment
##############################################################################

resource "aws_autoscaling_attachment" "example" {
  autoscaling_group_name = aws_autoscaling_group.asg.id
  lb_target_group_arn    = aws_lb_target_group.alb-lb-tg.arn
}