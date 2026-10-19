# SPDX-FileCopyrightText: 2026 Moon Technologies LLC
# SPDX-License-Identifier: AGPL-3.0-or-later

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.69"
    }
  }

  # State for every account stage lives in the management account's state
  # bucket, one key per account. The first apply runs with a local backend; see
  # docs/runbooks/bootstrap.md. Bucket and key come from -backend-config.
  backend "s3" {
    use_lockfile = true
    encrypt      = true
  }
}
