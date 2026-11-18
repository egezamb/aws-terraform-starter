terraform {
  # 1.7 is the first release with mock_provider, which tests/plan.tftest.hcl needs.
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.68"
    }
    # s3.tf uses random_id for the bucket suffix. Declared, so its version is pinned like aws's.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "ege-zambelli"
    }
  }
}

data "aws_partition" "current" {}
