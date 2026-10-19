# SPDX-FileCopyrightText: 2026 Moon Technologies LLC
# SPDX-License-Identifier: AGPL-3.0-or-later

# GitHub Actions reaches this account only through OIDC, never with stored
# keys. mh-ci-plan is read-only and serves pull requests and main;
# mh-ci-apply-<env> is trusted only for jobs in that GitHub environment (prod's
# environment requires a manual approval). Every role CI creates must carry the
# mh-boundary permissions boundary, so CI can't grant itself more than it has.

locals {
  ci_enabled = length(var.ci_environments) > 0
  oidc_host  = "token.actions.githubusercontent.com"
  repo_sub   = "repo:${var.github_repository}"

  boundary_name = "mh-boundary"
  boundary_arn  = "arn:aws:iam::${var.account_id}:policy/${local.boundary_name}"

  # Roles CI must never be able to change: its own, and the cross-account
  # administration role the bootstrap uses.
  protected_role_arns = [
    "arn:aws:iam::${var.account_id}:role/mh-ci-*",
    "arn:aws:iam::${var.account_id}:role/OrganizationAccountAccessRole",
    "arn:aws:iam::${var.account_id}:role/aws-reserved/*",
  ]
}

resource "aws_iam_openid_connect_provider" "github" {
  count = local.ci_enabled ? 1 : 0

  url            = "https://${local.oidc_host}"
  client_id_list = ["sts.amazonaws.com"]
}

resource "aws_iam_policy" "boundary" {
  count = local.ci_enabled ? 1 : 0

  name        = local.boundary_name
  description = "Ceiling for CI and every role CI creates."
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "Ceiling"
        Effect   = "Allow"
        Action   = "*"
        Resource = "*"
      },
      {
        Sid    = "NewRolesCarryTheBoundary"
        Effect = "Deny"
        Action = [
          "iam:AttachRolePolicy", "iam:CreateRole", "iam:DeleteRolePolicy", "iam:DetachRolePolicy",
          "iam:PutRolePermissionsBoundary", "iam:PutRolePolicy",
        ]
        Resource  = "*"
        Condition = { StringNotEquals = { "iam:PermissionsBoundary" = local.boundary_arn } }
      },
      {
        Sid      = "BoundaryCantBeRemoved"
        Effect   = "Deny"
        Action   = ["iam:DeleteRolePermissionsBoundary", "iam:DeleteUserPermissionsBoundary"]
        Resource = "*"
      },
      {
        Sid    = "BoundaryCantBeEdited"
        Effect = "Deny"
        Action = [
          "iam:CreatePolicyVersion", "iam:DeletePolicy", "iam:DeletePolicyVersion", "iam:SetDefaultPolicyVersion",
        ]
        Resource = local.boundary_arn
      },
      {
        Sid    = "ProtectedRolesAreUntouchable"
        Effect = "Deny"
        Action = [
          "iam:AttachRolePolicy", "iam:DeleteRole", "iam:DeleteRolePolicy", "iam:DetachRolePolicy",
          "iam:PassRole", "iam:PutRolePermissionsBoundary", "iam:PutRolePolicy", "iam:TagRole",
          "iam:UntagRole", "iam:UpdateAssumeRolePolicy", "iam:UpdateRole",
        ]
        Resource = local.protected_role_arns
      },
      {
        Sid    = "OidcTrustIsBootstrapOnly"
        Effect = "Deny"
        Action = [
          "iam:AddClientIDToOpenIDConnectProvider", "iam:CreateOpenIDConnectProvider",
          "iam:DeleteOpenIDConnectProvider", "iam:RemoveClientIDFromOpenIDConnectProvider",
          "iam:UpdateOpenIDConnectProviderThumbprint",
        ]
        Resource = "*"
      },
      {
        Sid    = "NoLongLivedCredentials"
        Effect = "Deny"
        Action = [
          "iam:CreateAccessKey", "iam:CreateLoginProfile", "iam:CreateUser", "iam:UpdateLoginProfile",
        ]
        Resource = "*"
      },
      {
        Sid    = "StateStoreIsBootstrapOnly"
        Effect = "Deny"
        Action = [
          "s3:DeleteBucket", "s3:DeleteBucketPolicy", "s3:PutBucketPolicy", "s3:PutBucketVersioning",
          "s3:PutEncryptionConfiguration", "s3:PutLifecycleConfiguration",
        ]
        Resource = "arn:aws:s3:::${local.state_bucket}"
      },
      {
        Sid      = "StateKeyIsBootstrapOnly"
        Effect   = "Deny"
        Action   = ["kms:DisableKey", "kms:PutKeyPolicy", "kms:ScheduleKeyDeletion"]
        Resource = aws_kms_key.state.arn
      },
      {
        Sid      = "NoOrganizationOrAccountChanges"
        Effect   = "Deny"
        Action   = ["account:*", "organizations:*"]
        Resource = "*"
      },
    ]
  })
}

locals {
  state_access = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadState"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
      },
      {
        Sid      = "TakeAndReleaseLocks"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.state.arn}/*.tflock"
      },
      {
        Sid      = "UseStateKey"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
        Resource = aws_kms_key.state.arn
      },
    ]
  }
}

resource "aws_iam_role" "ci_plan" {
  count = local.ci_enabled ? 1 : 0

  name                 = "mh-ci-plan"
  description          = "Read-only Terraform plans from pull requests and main."
  max_session_duration = 3600
  permissions_boundary = aws_iam_policy.boundary[0].arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github[0].arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "${local.oidc_host}:aud" = "sts.amazonaws.com" }
        StringLike = {
          "${local.oidc_host}:sub" = ["${local.repo_sub}:pull_request", "${local.repo_sub}:ref:refs/heads/main"]
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ci_plan_read_only" {
  count = local.ci_enabled ? 1 : 0

  role       = aws_iam_role.ci_plan[0].name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "ci_plan_state" {
  count = local.ci_enabled ? 1 : 0

  name   = "terraform-state"
  role   = aws_iam_role.ci_plan[0].id
  policy = jsonencode(local.state_access)
}

resource "aws_iam_role" "ci_apply" {
  for_each = toset(var.ci_environments)

  name                 = "mh-ci-apply-${each.key}"
  description          = "Terraform apply for the ${each.key} GitHub environment."
  max_session_duration = 7200
  permissions_boundary = aws_iam_policy.boundary[0].arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github[0].arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_host}:aud" = "sts.amazonaws.com"
          "${local.oidc_host}:sub" = "${local.repo_sub}:environment:${each.key}"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ci_apply_admin" {
  for_each = aws_iam_role.ci_apply

  role       = each.value.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
