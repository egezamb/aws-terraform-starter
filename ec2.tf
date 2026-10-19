# The instance type decides the CPU architecture: t3 is x86_64, t4g (Graviton) is arm64. An AMI
# for the other one would fail at launch.
data "aws_ec2_instance_type" "web" {
  instance_type = var.instance_type
}

locals {
  ami_architecture = contains(data.aws_ec2_instance_type.web.supported_architectures, "arm64") ? "arm64" : "x86_64"
}

# The current Amazon Linux 2023 AMI, from the public SSM parameter AWS keeps up to date for it.
# A name filter such as "al2023-ami-*-x86_64" also matches the minimal and ECS-optimized AMIs,
# and most_recent can pick one of those instead of the standard image.
data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-${local.ami_architecture}"
}

resource "aws_security_group" "web" {
  name        = "${var.project_name}-web-sg"
  description = "Allow HTTP and SSH inbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH only when a CIDR is given; the default opens no port 22 at all.
  dynamic "ingress" {
    for_each = var.allowed_ssh_cidr == null ? [] : [var.allowed_ssh_cidr]
    content {
      description = "SSH from allowed CIDR"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  # Outbound only what the instance uses: dnf mirrors over HTTP/HTTPS. DNS goes to the VPC resolver,
  # which security groups do not filter.
  egress {
    description = "HTTP to package mirrors"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # trivy:ignore:AWS-0104 dnf mirrors have no fixed addresses
  }

  egress {
    description = "HTTPS to package mirrors and AWS APIs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # trivy:ignore:AWS-0104 dnf mirrors and AWS endpoints have no fixed addresses
  }

  tags = {
    Name = "${var.project_name}-web-sg"
  }
}

resource "aws_instance" "web" {
  ami                    = data.aws_ssm_parameter.al2023_ami.insecure_value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]

  user_data = <<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y httpd
              systemctl enable --now httpd
              echo "<h1>Hello from ${var.project_name} — deployed by Terraform</h1>" > /var/www/html/index.html
              EOF

  user_data_replace_on_change = true

  # Encrypted at rest with the AWS-managed EBS key; gp3 is cheaper than gp2 for the same size.
  root_block_device {
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  tags = {
    Name = "${var.project_name}-web-server"
  }
}
