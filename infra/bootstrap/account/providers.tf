# SPDX-FileCopyrightText: 2026 Moon Technologies LLC
# SPDX-License-Identifier: AGPL-3.0-or-later

# Runs with management-account credentials. For a member account it assumes
# the OrganizationAccountAccessRole Organizations created there; for the
# management account itself (assume_role_name = null) it uses the caller's own
# credentials. allowed_account_ids stops it touching any other account.
provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id]

  dynamic "assume_role" {
    for_each = var.assume_role_name == null ? [] : [var.assume_role_name]
    content {
      role_arn     = "arn:aws:iam::${var.account_id}:role/${assume_role.value}"
      session_name = "moonlight-bootstrap"
    }
  }

  default_tags {
    tags = {
      Project   = "moonlight-hotel"
      Owner     = "Moon Technologies LLC"
      ManagedBy = "terraform"
      Stack     = "bootstrap/account"
      Account   = var.account_name
    }
  }
}
