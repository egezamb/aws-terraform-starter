# Plan-only tests with mocked providers: no AWS account or credentials needed.
#   terraform init -backend=false && terraform test
# They pin the secure defaults, so a change that loosens one fails here before review.

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["eu-central-1a", "eu-central-1b"]
    }
  }
  mock_data "aws_ami" {
    defaults = {
      id = "ami-0123456789abcdef0"
    }
  }
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{}"
    }
  }
}

mock_provider "random" {}

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
