# SPDX-FileCopyrightText: 2026 Moon Technologies LLC
# SPDX-License-Identifier: AGPL-3.0-or-later

output "trail_arn" {
  value = aws_cloudtrail.org.arn
}

output "trail_bucket" {
  value = aws_s3_bucket.trail.bucket
}

output "trail_kms_key_arn" {
  value = aws_kms_key.trail.arn
}
