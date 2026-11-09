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

  # Assign [] explicitly when both ports are closed: omitting inline rules preserves old rules.
  ingress = concat(
    [for cidrs in(length(var.allowed_http_cidrs) == 0 ? [] : [var.allowed_http_cidrs]) : {
      description      = "HTTP from allowed CIDRs"
      from_port        = 80
      to_port          = 80
      protocol         = "tcp"
      cidr_blocks      = cidrs
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      security_groups  = []
      self             = false
    }],
    [for cidr in(var.allowed_ssh_cidr == null ? [] : [var.allowed_ssh_cidr]) : {
      description      = "SSH from allowed CIDR"
      from_port        = 22
      to_port          = 22
      protocol         = "tcp"
      cidr_blocks      = [cidr]
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      security_groups  = []
      self             = false
    }]
  )

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

# A shell without an open port: Session Manager. Amazon Linux 2023 ships the SSM agent, and this
# role lets it register (`aws ssm start-session --target <instance-id>`). No key pair to keep.
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "web" {
  name               = "${var.project_name}-web"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "web_ssm" {
  role       = aws_iam_role.web.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "web" {
  name = "${var.project_name}-web"
  role = aws_iam_role.web.name
}

resource "aws_instance" "web" {
  ami                    = data.aws_ssm_parameter.al2023_ami.insecure_value
  instance_type          = var.instance_type
  key_name               = var.ssh_key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.web.name

  user_data = templatefile("${path.module}/templates/web-bootstrap.sh.tftpl", {
    project_name = var.project_name
  })

  user_data_replace_on_change = true

  # Encrypted at rest with the AWS-managed EBS key; gp3 is cheaper than gp2 for the same size.
  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size_gib
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
