variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Project name used to tag and prefix resources"
  type        = string
  default     = "aws-terraform-starter"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC, from /16 to /28"
  type        = string
  default     = "10.0.0.0/16"

  # AWS refuses any other size, but only at apply, after the plan looked fine.
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && can(regex("^[0-9.]+/(1[6-9]|2[0-8])$", var.vpc_cidr))
    error_message = "vpc_cidr must be an IPv4 CIDR from /16 to /28, such as 10.0.0.0/16."
  }
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type (default is free-tier eligible). x86 (t3) or Graviton (t4g): the AMI follows the type's architecture."
  type        = string
  default     = "t3.micro"
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH into the instance, e.g. your IP as \"203.0.113.7/32\". Unset (the default) means no SSH port is opened at all."
  type        = string
  default     = null

  validation {
    condition     = var.allowed_ssh_cidr == null || (can(cidrhost(var.allowed_ssh_cidr, 0)) && var.allowed_ssh_cidr != "0.0.0.0/0")
    error_message = "allowed_ssh_cidr must be a CIDR such as 203.0.113.7/32, and not 0.0.0.0/0 (SSH open to the whole internet)."
  }
}

variable "flow_log_retention_days" {
  description = "Days the VPC flow logs are kept in S3 before they are deleted"
  type        = number
  default     = 30

  validation {
    condition     = var.flow_log_retention_days >= 1
    error_message = "flow_log_retention_days must be at least 1."
  }
}
