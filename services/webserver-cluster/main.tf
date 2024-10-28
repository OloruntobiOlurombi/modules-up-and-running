locals {
  http_port = 80
  any_port = 0
  any_protocol = "-1"
  tcp_protocol = "tcp"
  all_ips = ["0.0.0.0/0"]
}

terraform {
  required_providers {
    # Make sure this section no longer includes the template provider
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
  }
}


# terraform {
#     backend "s3" {
#         bucket = "terraform-up-and-running-state-tobi-2024"
#         #key = "global/s3/terraform.tfstate"
#         key = "stage/services/webserver-cluster/terraform.tfstate"
#         region = "us-east-2"
#         profile = "tobi"

#         # Replace this with your DynamoDB table name!
#         dynamodb_table = "terraform-up-and-running-locks"
#         encrypt = true 
#     }
# }

data "terraform_remote_state" "db" {
     backend = "s3" 
     config = {
        bucket = var.db_remote_state_bucket # "terraform-up-and-running-state-tobi-2024"
        key = var.db_remote_state_key # "stage/data-stores/mysql/terraform.tfstate"
        region = "us-east-2"
        profile = "tobi"
     }
}

provider "aws" {
  region = "us-east-1"
  profile = "tobi"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "instance" {
  name = "terraform-example-instance"

  ingress {
    from_port = var.server_port
    to_port = var.server_port
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 8080
    to_port = 8080
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 80 
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = -1
    cidr_blocks = ["0.0.0.0/0"]

  }
}


resource "aws_launch_configuration" "example" {
  image_id = "ami-07caf09b362be10b8"
  instance_type = var.instance_type
  security_groups = [aws_security_group.instance.id]
  user_data = templatefile("${path.module}/user-data.sh", {
    server_port = var.server_port,
    db_address = data.terraform_remote_state.db.outputs.address,
    db_port = data.terraform_remote_state.db.outputs.port

  })

   lifecycle {
      create_before_destroy = true
   }
  }

resource "aws_autoscaling_group" "example" {
  launch_configuration = aws_launch_configuration.example.name
  vpc_zone_identifier = data.aws_subnets.default.ids

  target_group_arns = [aws_lb_target_group.asg.arn]
  health_check_type = "ELB"

  min_size = var.min_size
  max_size = var.max_size

  tag {
    key = "Name"
    value = var.cluster_name
    propagate_at_launch = true 
  }
}

resource "aws_lb" "example" {
    name = "terraform-asg-example"
    load_balancer_type = "application"
    subnets = data.aws_subnets.default.ids
    security_groups = [aws_security_group.alb.id]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.example.arn
  port = local.http_port 
  protocol = "HTTP"
  # By default, return a simple 404 page 
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code = 404
    }
  }
}

resource "aws_security_group" "alb" {
    name = "${var.cluster_name}-alb" #"terraform-example-alb"
    # Allow inbound HTTP requests
    ingress {
      from_port = local.http_port
      to_port = local.http_port
      protocol = local.tcp_protocol
      cidr_blocks = local.all_ips
    }

    # Allow all outbound requests 
    egress {
      from_port = local.any_port
      to_port = local.any_port
      protocol = local.any_protocol
      cidr_blocks = local.all_ips
    }
}

resource "aws_security_group_rule" "allow_http_inbound" {
  type = "ingress"
  security_group_id = aws_security_group.alb.id

  from_port = local.http_port
  to_port = local.http_port 
  protocol = local.tcp_protocol
  cidr_blocks = local.all_ips
}

resource "aws_security_group_rule" "allow_all_outbound" {
  type = "egress"
  security_group_id = aws_security_group.alb.id

  from_port = local.any_port 
  to_port = local.any_port 
  protocol = local.any_protocol
  cidr_blocks = local.all_ips
}

resource "aws_lb_target_group" "asg" {
    name = "terraform-asg-example"
    port = var.server_port 
    protocol = "HTTP"
    vpc_id = data.aws_vpc.default.id  

    health_check {
      path = "/"
      protocol = "HTTP"
      matcher = "200"
      interval = 15 
      timeout = 3
      healthy_threshold = 2 
      unhealthy_threshold = 2 
    }
}

resource "aws_lb_listener_rule" "asg" {
    listener_arn = "${aws_lb_listener.http.arn}"
    priority = 100 

    action {
      type = "forward"
      target_group_arn = "${aws_lb_target_group.asg.arn}"
    }

    condition {
      path_pattern {
        values = ["*"]
      }
  }   
}