# Plan-only tests with mocked providers: no AWS account or credentials needed.
#   terraform init -backend=false && terraform test
# They pin the secure defaults, so a change that loosens one fails here before review.

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["eu-central-1a", "eu-central-1b"]
    }
  }
  mock_data "aws_ec2_instance_type" {
    defaults = {
      supported_architectures = ["i386", "x86_64"]
    }
  }
  mock_data "aws_ssm_parameter" {
    defaults = {
      insecure_value = "ami-0123456789abcdef0"
    }
  }
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{}"
    }
  }
}

mock_provider "random" {}

# The provider checks the flow log's destination ARN, and the mock's random strings aren't ARNs.
override_resource {
  target = aws_s3_bucket.flow_logs
  values = {
    arn = "arn:aws:s3:::aws-terraform-starter-flow-logs-mock"
  }
}

run "ssh_is_closed_by_default" {
  command = plan

  assert {
    condition     = alltrue([for rule in aws_security_group.web.ingress : rule.from_port != 22])
    error_message = "No SSH port may be open unless allowed_ssh_cidr is set."
  }
  assert {
    condition     = anytrue([for rule in aws_security_group.web.ingress : rule.from_port == 80])
    error_message = "HTTP (80) must stay open for the web server."
  }
}

run "allowed_ssh_cidr_opens_ssh_to_that_cidr_only" {
  command = plan

  variables {
    allowed_ssh_cidr = "203.0.113.7/32"
  }

  assert {
    condition = anytrue([
      for rule in aws_security_group.web.ingress :
      rule.from_port == 22 && rule.to_port == 22 && length(rule.cidr_blocks) == 1 && contains(rule.cidr_blocks, "203.0.113.7/32")
    ])
    error_message = "allowed_ssh_cidr must open port 22 to exactly that CIDR."
  }
}

run "ssh_open_to_the_whole_internet_is_refused" {
  command = plan

  variables {
    allowed_ssh_cidr = "0.0.0.0/0"
  }

  expect_failures = [var.allowed_ssh_cidr]
}

run "the_instance_has_an_encrypted_disk_and_imdsv2" {
  command = plan

  assert {
    condition     = aws_instance.web.root_block_device[0].encrypted
    error_message = "The root volume must be encrypted."
  }
  assert {
    condition     = aws_instance.web.metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 must be required (http_tokens = required)."
  }
}

run "the_bucket_is_private_versioned_encrypted_and_tls_only" {
  command = plan

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.assets.block_public_acls,
      aws_s3_bucket_public_access_block.assets.block_public_policy,
      aws_s3_bucket_public_access_block.assets.ignore_public_acls,
      aws_s3_bucket_public_access_block.assets.restrict_public_buckets,
    ])
    error_message = "All four public access blocks must be on."
  }
  assert {
    condition     = aws_s3_bucket_versioning.assets.versioning_configuration[0].status == "Enabled"
    error_message = "Versioning must be enabled."
  }
  assert {
    condition = anytrue([
      for rule in aws_s3_bucket_server_side_encryption_configuration.assets.rule :
      rule.apply_server_side_encryption_by_default[0].sse_algorithm == "AES256"
    ])
    error_message = "Objects must be encrypted at rest."
  }
  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.assets_tls_only.statement :
      s.effect == "Deny" && anytrue([for c in s.condition : c.variable == "aws:SecureTransport" && contains(c.values, "false")])
    ])
    error_message = "The bucket policy must deny requests that don't use TLS."
  }
}

run "an_unknown_environment_is_refused" {
  command = plan

  variables {
    environment = "qa"
  }

  expect_failures = [var.environment]
}

run "the_ami_is_the_standard_amazon_linux_2023_image" {
  command = plan

  assert {
    condition     = data.aws_ssm_parameter.al2023_ami.name == "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
    error_message = "The AMI must come from AWS's public parameter for the standard AL2023 image, not a name filter."
  }
  assert {
    condition     = aws_instance.web.ami == "ami-0123456789abcdef0"
    error_message = "The instance must run the AMI the parameter names."
  }
}

run "a_graviton_instance_type_gets_the_arm64_ami" {
  command = plan

  variables {
    instance_type = "t4g.micro"
  }

  override_data {
    target = data.aws_ec2_instance_type.web
    values = {
      supported_architectures = ["arm64"]
    }
  }

  assert {
    condition     = data.aws_ssm_parameter.al2023_ami.name == "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
    error_message = "An arm64 instance type must get the arm64 AL2023 AMI."
  }
}

run "the_default_security_group_allows_nothing" {
  # The rule sets are computed, so only known after an apply: the mocked one, no AWS involved.
  command = apply

  assert {
    condition     = length(aws_default_security_group.default.ingress) == 0 && length(aws_default_security_group.default.egress) == 0
    error_message = "The VPC's default security group must have no rules."
  }
}

run "the_vpc_records_its_traffic_in_flow_logs_that_expire" {
  command = plan

  assert {
    condition     = aws_flow_log.vpc.traffic_type == "ALL" && aws_flow_log.vpc.log_destination_type == "s3"
    error_message = "The VPC must log accepted and rejected traffic to S3, which needs no IAM role."
  }
  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.flow_logs.rule[0].expiration[0].days == 30
    error_message = "Flow logs expire after flow_log_retention_days (30 by default), so the bucket does not grow forever."
  }
  assert {
    condition     = aws_s3_bucket_public_access_block.flow_logs.block_public_acls && aws_s3_bucket_public_access_block.flow_logs.restrict_public_buckets
    error_message = "The flow log bucket must block public access like the assets bucket."
  }
}

run "the_flow_log_bucket_is_an_output" {
  command = apply

  assert {
    condition     = output.flow_logs_bucket == aws_s3_bucket.flow_logs.bucket
    error_message = "The flow log bucket's name is an output, so you know where to read the logs."
  }
}

run "a_vpc_cidr_aws_cannot_create_is_refused" {
  command = plan

  # AWS only creates VPCs from /16 to /28; a /8 would fail at apply, after other resources exist.
  variables {
    vpc_cidr = "10.0.0.0/8"
  }

  expect_failures = [var.vpc_cidr]
}

run "a_vpc_cidr_that_is_not_a_cidr_is_refused" {
  command = plan

  variables {
    vpc_cidr = "10.0.0.0"
  }

  expect_failures = [var.vpc_cidr]
}

run "a_public_subnet_outside_the_vpc_is_refused" {
  command = plan

  variables {
    vpc_cidr           = "10.0.0.0/16"
    public_subnet_cidr = "10.1.1.0/24"
  }

  expect_failures = [aws_subnet.public]
}

run "a_public_subnet_larger_than_the_vpc_is_refused" {
  command = plan

  variables {
    vpc_cidr           = "10.0.0.0/24"
    public_subnet_cidr = "10.0.0.0/16"
  }

  expect_failures = [aws_subnet.public]
}

run "a_public_subnet_inside_a_custom_vpc_is_accepted" {
  command = plan

  variables {
    vpc_cidr           = "172.16.0.0/20"
    public_subnet_cidr = "172.16.15.0/24"
  }

  assert {
    condition     = aws_subnet.public.cidr_block == "172.16.15.0/24"
    error_message = "A subnet inside the VPC must be planned as given."
  }
}

run "the_flow_log_bucket_is_tls_only_and_writable_only_by_this_accounts_log_delivery" {
  command = plan

  assert {
    condition     = aws_s3_bucket_policy.flow_logs.bucket == aws_s3_bucket.flow_logs.id
    error_message = "The flow log bucket must have its own bucket policy, managed here."
  }
  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.flow_logs.statement :
      s.effect == "Deny" && anytrue([for c in s.condition : c.variable == "aws:SecureTransport" && contains(c.values, "false")])
    ])
    error_message = "The flow log bucket policy must deny requests that don't use TLS, like the assets bucket's."
  }
  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.flow_logs.statement :
      s.effect == "Allow" && contains(s.actions, "s3:PutObject")
      && anytrue([for p in s.principals : contains(p.identifiers, "delivery.logs.amazonaws.com")])
      && anytrue([for c in s.condition : c.variable == "aws:SourceAccount"])
    ])
    error_message = "Log delivery may write only on behalf of this account (aws:SourceAccount), against the confused-deputy problem."
  }
}
