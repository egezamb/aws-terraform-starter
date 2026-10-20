# VPC flow logs: one record per accepted or rejected connection, so blocked scans and unexpected
# outbound traffic leave a trace. They go to S3 because a CloudWatch destination needs an IAM
# role; S3 delivery does not. Old logs expire so the bucket does not grow forever.
resource "aws_flow_log" "vpc" {
  vpc_id               = aws_vpc.main.id
  traffic_type         = "ALL"
  log_destination_type = "s3"
  log_destination      = aws_s3_bucket.flow_logs.arn

  tags = {
    Name = "${var.project_name}-vpc-flow-log"
  }
}

# trivy:ignore:AWS-0089 This bucket only receives logs; logging access to a log bucket would need yet another bucket.
# trivy:ignore:AWS-0090 Versioning would keep every expired log as a noncurrent version and defeat the lifecycle rule.
resource "aws_s3_bucket" "flow_logs" {
  bucket        = "${var.project_name}-flow-logs-${random_id.bucket_suffix.hex}"
  force_destroy = true

  tags = {
    Name    = "${var.project_name}-flow-logs"
    Purpose = "VPC flow logs"
  }
}

# trivy:ignore:AWS-0132 SSE-S3 (AES256) is enough for flow logs; a customer-managed KMS key costs $1/month plus requests.
resource "aws_s3_bucket_server_side_encryption_configuration" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id

  rule {
    id     = "expire-flow-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.flow_log_retention_days
    }
  }
}
