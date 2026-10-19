# SPDX-FileCopyrightText: 2026 Moon Technologies LLC
# SPDX-License-Identifier: AGPL-3.0-or-later

# Runs against a mocked AWS provider: nothing reaches AWS. Plan only, with
# mocked values applied during plan, because the organization and accounts are
# prevent_destroy and a test apply could never clean them up.
mock_provider "aws" {
  override_during = plan

  mock_resource "aws_organizations_policy" {
    defaults = { id = "p-testpolicy" }
  }
  mock_resource "aws_organizations_account" {
    defaults = { id = "222222222222" }
  }
  override_resource {
    target = aws_organizations_organization.this
    values = {
      id    = "o-test123456"
      roots = [{ id = "r-test", arn = "arn:aws:organizations::111111111111:root/o-test123456/r-test", name = "Root", policy_types = [] }]
    }
  }
}

override_resource {
  override_during = plan
  target          = aws_organizations_organizational_unit.security
  values          = { id = "ou-test-security1" }
}

override_resource {
  override_during = plan
  target          = aws_organizations_organizational_unit.workloads
  values          = { id = "ou-test-workload1" }
}

override_resource {
  override_during = plan
  target          = aws_organizations_account.member["log-archive"]
  values          = { id = "333333333333" }
}

variables {
  management_account_id = "111111111111"
  allowed_regions       = ["us-east-1", "eu-west-2"]
  accounts = {
    "prod"        = { name = "hotel-prod", email = "prod@example.com", ou = "workloads" }
    "staging"     = { name = "hotel-staging", email = "staging@example.com", ou = "workloads" }
    "log-archive" = { name = "log-archive", email = "logs@example.com", ou = "security" }
  }
}

run "builds_organization" {
  command = plan

  assert {
    condition     = aws_organizations_account.member["prod"].parent_id == aws_organizations_organizational_unit.workloads.id
    error_message = "prod belongs in the Workloads OU"
  }
  assert {
    condition     = aws_organizations_account.member["log-archive"].parent_id == aws_organizations_organizational_unit.security.id
    error_message = "log-archive belongs in the Security OU"
  }
  assert {
    condition     = length(aws_organizations_policy.scp) == 5 && length(aws_organizations_policy_attachment.scp) == 9
    error_message = "five SCPs: four on both OUs, the log-archive guard on Security only"
  }
  assert {
    condition = (
      jsondecode(aws_organizations_policy.scp["mh-deny-other-regions"].content).Statement[0].Condition.StringNotEquals["aws:RequestedRegion"]
      == ["us-east-1", "eu-west-2"]
    )
    error_message = "the region SCP must deny everything outside allowed_regions"
  }
  assert {
    condition     = contains(jsondecode(aws_organizations_policy.scp["mh-deny-other-regions"].content).Statement[0].NotAction, "cloudfront:*")
    error_message = "global services must be exempt from the region SCP"
  }
  assert {
    condition     = output.log_archive_bucket == "mh-org-trail-333333333333"
    error_message = "the trail bucket name derives from the log-archive account"
  }
  assert {
    condition = (
      jsondecode(aws_organizations_policy.scp["mh-protect-log-archive"].content).Statement[0].Resource[0]
      == "arn:aws:s3:::mh-org-trail-333333333333"
    )
    error_message = "the log-archive guard must target the trail bucket"
  }
}

run "requires_core_accounts" {
  command = plan
  variables {
    accounts = {
      "prod" = { name = "hotel-prod", email = "prod@example.com", ou = "workloads" }
    }
  }
  expect_failures = [var.accounts]
}

run "requires_distinct_emails" {
  command = plan
  variables {
    accounts = {
      "prod"        = { name = "hotel-prod", email = "same@example.com", ou = "workloads" }
      "staging"     = { name = "hotel-staging", email = "SAME@example.com", ou = "workloads" }
      "log-archive" = { name = "log-archive", email = "logs@example.com", ou = "security" }
    }
  }
  expect_failures = [var.accounts]
}

run "requires_us_east_1" {
  command = plan
  variables {
    allowed_regions = ["eu-west-2"]
  }
  expect_failures = [var.allowed_regions]
}

run "requires_cloudtrail_trusted_access" {
  command = plan
  variables {
    aws_service_access_principals = ["sso.amazonaws.com"]
  }
  expect_failures = [var.aws_service_access_principals]
}
