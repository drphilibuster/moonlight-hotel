# SPDX-FileCopyrightText: 2026 Moon Technologies LLC
# SPDX-License-Identifier: AGPL-3.0-or-later

# Mocked AWS provider, plan only (the state bucket and key are prevent_destroy).
mock_provider "aws" {
  override_during = plan

  mock_resource "aws_kms_key" {
    defaults = {
      arn    = "arn:aws:kms:us-east-1:222222222222:key/00000000-0000-0000-0000-000000000000"
      key_id = "00000000-0000-0000-0000-000000000000"
    }
  }
  mock_resource "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::mh-tfstate-222222222222" }
  }
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::222222222222:oidc-provider/token.actions.githubusercontent.com" }
  }
  mock_resource "aws_iam_policy" {
    defaults = { arn = "arn:aws:iam::222222222222:policy/mh-boundary" }
  }
}

variables {
  account_id      = "222222222222"
  account_name    = "prod"
  ci_environments = ["prod"]
}

run "member_account_with_ci" {
  command = plan

  assert {
    condition     = aws_s3_bucket.state.bucket == "mh-tfstate-222222222222"
    error_message = "state bucket is named for its account"
  }
  assert {
    condition = (
      jsondecode(aws_iam_role.ci_apply["prod"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"]
      == "repo:drphilibuster/moonlight-hotel:environment:prod"
    )
    error_message = "the apply role must trust only jobs in the prod environment"
  }
  assert {
    condition     = aws_iam_role.ci_apply["prod"].permissions_boundary == "arn:aws:iam::222222222222:policy/mh-boundary"
    error_message = "the apply role must carry the boundary"
  }
  assert {
    condition = contains(
      jsondecode(aws_iam_role.ci_plan[0].assume_role_policy).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"],
      "repo:drphilibuster/moonlight-hotel:pull_request"
    )
    error_message = "the plan role serves pull requests"
  }
  assert {
    condition = (
      [for s in jsondecode(aws_iam_policy.boundary[0].policy).Statement : s if s.Sid == "NewRolesCarryTheBoundary"][0].Condition.StringNotEquals["iam:PermissionsBoundary"]
      == "arn:aws:iam::222222222222:policy/mh-boundary"
    )
    error_message = "roles CI creates must be forced to carry the boundary"
  }
  assert {
    condition = contains(
      [for s in jsondecode(aws_iam_policy.boundary[0].policy).Statement : s if s.Sid == "ProtectedRolesAreUntouchable"][0].Resource,
      "arn:aws:iam::222222222222:role/OrganizationAccountAccessRole"
    )
    error_message = "CI must not be able to rewrite the cross-account admin role"
  }
  assert {
    condition     = aws_s3_bucket_versioning.state.versioning_configuration[0].status == "Enabled"
    error_message = "state must be versioned"
  }
  assert {
    condition = (
      one(one(aws_s3_bucket_server_side_encryption_configuration.state.rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms"
    )
    error_message = "state must be encrypted with the account's KMS key"
  }
  assert {
    condition     = jsondecode(aws_s3_bucket_policy.state.policy).Statement[0].Condition.Bool["aws:SecureTransport"] == "false"
    error_message = "state bucket must refuse plain HTTP"
  }
}

run "management_account_has_no_ci" {
  command = plan
  variables {
    account_id       = "111111111111"
    account_name     = "management"
    assume_role_name = null
    ci_environments  = []
  }
  assert {
    condition     = length(aws_iam_role.ci_plan) == 0 && length(aws_iam_role.ci_apply) == 0 && length(aws_iam_openid_connect_provider.github) == 0
    error_message = "CI never reaches the management account"
  }
}

run "rejects_unknown_account_name" {
  command = plan
  variables {
    account_name = "sandbox"
  }
  expect_failures = [var.account_name]
}
