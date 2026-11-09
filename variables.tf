variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "eu-central-1"
  nullable    = false
}

variable "project_name" {
  description = "Project name used to tag and prefix resources"
  type        = string
  default     = "aws-terraform-starter"
  nullable    = false
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,42}[a-z0-9]$", var.project_name))
    error_message = "project_name must be 2-44 lowercase letters, digits or hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"
  nullable    = false

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC, from /16 to /28"
  type        = string
  default     = "10.0.0.0/16"
  nullable    = false

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
  nullable    = false
  validation {
    condition     = can(cidrnetmask(var.public_subnet_cidr)) && can(regex("/(1[6-9]|2[0-8])$", var.public_subnet_cidr))
    error_message = "public_subnet_cidr must be an IPv4 CIDR from /16 to /28."
  }
}

variable "instance_type" {
  description = "EC2 instance type (default is free-tier eligible). x86 (t3) or Graviton (t4g): the AMI follows the type's architecture."
  type        = string
  default     = "t3.micro"
  nullable    = false
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH into the instance, e.g. your IP as \"203.0.113.7/32\". Unset (the default) means no SSH port is opened at all."
  type        = string
  default     = null

  validation {
    condition     = var.allowed_ssh_cidr == null || (can(cidrnetmask(var.allowed_ssh_cidr)) && can(regex("/([1-9]|[12][0-9]|3[0-2])$", var.allowed_ssh_cidr)))
    error_message = "allowed_ssh_cidr must be an IPv4 CIDR with a /1 to /32 prefix, such as 203.0.113.7/32. A /0 prefix opens SSH to the whole internet."
  }
}

variable "flow_log_retention_days" {
  description = "Days the VPC flow logs are kept in S3 before they are deleted"
  type        = number
  default     = 30
  nullable    = false

  validation {
    condition     = var.flow_log_retention_days >= 1 && floor(var.flow_log_retention_days) == var.flow_log_retention_days
    error_message = "flow_log_retention_days must be a whole number of days, at least 1."
  }
}

variable "ssh_key_name" {
  description = "Existing EC2 key pair name in aws_region for optional SSH; Session Manager needs no key pair."
  type        = string
  default     = null
  validation {
    condition     = var.ssh_key_name == null ? true : length(trimspace(var.ssh_key_name)) > 0
    error_message = "ssh_key_name must be null or a nonempty existing key pair name."
  }
}

variable "root_volume_size_gib" {
  description = "Encrypted gp3 root disk size in GiB; at least the standard AL2023 image size."
  type        = number
  default     = 8
  nullable    = false
  validation {
    condition     = var.root_volume_size_gib >= 8 && var.root_volume_size_gib <= 16384 && floor(var.root_volume_size_gib) == var.root_volume_size_gib
    error_message = "root_volume_size_gib must be a whole number from 8 to 16384."
  }
}

variable "asset_version_retention_days" {
  description = "Days to retain noncurrent asset versions; current objects are not expired."
  type        = number
  default     = 30
  nullable    = false
  validation {
    condition     = var.asset_version_retention_days >= 1 && floor(var.asset_version_retention_days) == var.asset_version_retention_days
    error_message = "asset_version_retention_days must be a positive whole number."
  }
}

variable "allow_bucket_force_destroy" {
  description = "Opt in to deleting all assets, versions and flow logs during terraform destroy. Leave false to protect nonempty buckets."
  type        = bool
  default     = false
  nullable    = false
}
