resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "assets" {
  bucket = "${var.project_name}-assets-${random_id.bucket_suffix.hex}"

  tags = {
    Name    = "${var.project_name}-assets"
    Purpose = "Static assets and Terraform demo storage"
  }
}

resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id

  versioning_configuration {
    status = "Enabled"
  }
}

# trivy:ignore:AWS-0132 SSE-S3 (AES256) is enough for demo assets; a customer-managed KMS key costs $1/month plus requests.
resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket = aws_s3_bucket.assets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Refuse any request that does not use TLS, so bucket traffic is never sent in plain text.
data "aws_iam_policy_document" "assets_tls_only" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.assets.arn, "${aws_s3_bucket.assets.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "assets" {
  bucket = aws_s3_bucket.assets.id
  policy = data.aws_iam_policy_document.assets_tls_only.json

  # The public access block must exist first, or a policy could briefly be evaluated without it.
  depends_on = [aws_s3_bucket_public_access_block.assets]
}

# Versioning keeps every overwritten or deleted object. Expire old versions after 30 days, so
# storage cost does not grow forever, and clean up uploads that never finished.
resource "aws_s3_bucket_lifecycle_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.assets]
}
