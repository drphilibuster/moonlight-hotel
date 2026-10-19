# SPDX-FileCopyrightText: 2026 Moon Technologies LLC
# SPDX-License-Identifier: AGPL-3.0-or-later

# Mocked providers, plan only (every resource here is prevent_destroy).
mock_provider "aws" {
  override_during = plan
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:us-east-1:333333333333:key/00000000-0000-0000-0000-000000000000" }
  }
}

mock_provider "aws" {
  alias           = "log_archive"
  override_during = plan
  mock_resource "aws_kms_key" {
    defaults = {
      arn    = "arn:aws:kms:us-east-1:333333333333:key/00000000-0000-0000-0000-000000000000"
      key_id = "00000000-0000-0000-0000-000000000000"
    }
  }
  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::mh-org-trail-333333333333"
      id  = "mh-org-trail-333333333333"
    }
  }
}

variables {
  management_account_id  = "111111111111"
  log_archive_account_id = "333333333333"
  organization_id        = "o-test123456"
}

run "org_trail" {
  command = plan

  assert {
    condition     = aws_cloudtrail.org.is_organization_trail && aws_cloudtrail.org.is_multi_region_trail && aws_cloudtrail.org.enable_log_file_validation
    error_message = "the trail must cover the whole organization, every region, with log file validation"
  }
  assert {
    condition     = aws_s3_bucket_versioning.trail.versioning_configuration[0].status == "Enabled"
    error_message = "trail logs must be versioned (Object Lock requires it)"
  }
  assert {
    condition = (
      one(one(aws_s3_bucket_server_side_encryption_configuration.trail.rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms"
    )
    error_message = "trail logs must be encrypted with the trail key"
  }
  assert {
    condition     = aws_s3_bucket.trail.bucket == "mh-org-trail-333333333333" && aws_s3_bucket.trail.object_lock_enabled
    error_message = "the bucket must match the organization stage's name and have Object Lock"
  }
  assert {
    condition = (
      jsondecode(aws_s3_bucket_policy.trail.policy).Statement[1].Condition.StringEquals["aws:SourceArn"]
      == "arn:aws:cloudtrail:us-east-1:111111111111:trail/mh-org-trail"
    )
    error_message = "only this trail may write to the bucket"
  }
  assert {
    condition = contains(
      jsondecode(aws_s3_bucket_policy.trail.policy).Statement[1].Resource,
      "arn:aws:s3:::mh-org-trail-333333333333/AWSLogs/o-test123456/*"
    )
    error_message = "member-account logs land under the organization prefix"
  }
}

run "keeps_logs_a_year" {
  command = plan
  variables {
    log_retention_days = 30
  }
  expect_failures = [var.log_retention_days]
}
