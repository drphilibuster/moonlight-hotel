# SPDX-FileCopyrightText: 2026 Moon Technologies LLC
# SPDX-License-Identifier: AGPL-3.0-or-later

# Runs with the management account's credentials (AWS_PROFILE or SSO), never
# from CI. allowed_account_ids stops it running against any other account.
provider "aws" {
  region              = var.region
  allowed_account_ids = [var.management_account_id]

  default_tags {
    tags = {
      Project   = "moonlight-hotel"
      Owner     = "Moon Technologies LLC"
      ManagedBy = "terraform"
      Stack     = "bootstrap/organization"
    }
  }
}
