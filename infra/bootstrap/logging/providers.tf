# SPDX-FileCopyrightText: 2026 Moon Technologies LLC
# SPDX-License-Identifier: AGPL-3.0-or-later

# The organization trail must be created in the management account; its bucket
# and key live in log-archive, where nobody else can delete them.
provider "aws" {
  region              = var.region
  allowed_account_ids = [var.management_account_id]
  default_tags { tags = local.tags }
}

provider "aws" {
  alias               = "log_archive"
  region              = var.region
  allowed_account_ids = [var.log_archive_account_id]

  assume_role {
    role_arn     = "arn:aws:iam::${var.log_archive_account_id}:role/OrganizationAccountAccessRole"
    session_name = "moonlight-bootstrap"
  }
  default_tags { tags = local.tags }
}

locals {
  tags = {
    Project   = "moonlight-hotel"
    Owner     = "Moon Technologies LLC"
    ManagedBy = "terraform"
    Stack     = "bootstrap/logging"
  }
}
