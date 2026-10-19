# SPDX-FileCopyrightText: 2026 Moon Technologies LLC
# SPDX-License-Identifier: AGPL-3.0-or-later

# The organization itself. To adopt an organization that already exists,
# import it first (docs/runbooks/bootstrap.md):
#   terraform import aws_organizations_organization.this <organization-id>
resource "aws_organizations_organization" "this" {
  feature_set                   = "ALL"
  aws_service_access_principals = var.aws_service_access_principals
  enabled_policy_types          = var.enabled_policy_types

  lifecycle {
    prevent_destroy = true
  }
}

locals {
  root_id = aws_organizations_organization.this.roots[0].id
}

resource "aws_organizations_organizational_unit" "security" {
  name      = "Security"
  parent_id = local.root_id
}

resource "aws_organizations_organizational_unit" "workloads" {
  name      = "Workloads"
  parent_id = local.root_id
}

locals {
  ou_ids = {
    security  = aws_organizations_organizational_unit.security.id
    workloads = aws_organizations_organizational_unit.workloads.id
  }
}

resource "aws_organizations_account" "member" {
  for_each = var.accounts

  name      = each.value.name
  email     = each.value.email
  parent_id = local.ou_ids[each.value.ou]

  # The role Organizations creates in each new account, which the account and
  # logging stages assume. The API never returns these two settings, so
  # Terraform must not try to reconcile them.
  role_name                  = "OrganizationAccountAccessRole"
  iam_user_access_to_billing = "DENY"
  close_on_deletion          = false

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [role_name, iam_user_access_to_billing]
  }
}
