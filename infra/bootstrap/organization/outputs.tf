# SPDX-FileCopyrightText: 2026 Moon Technologies LLC
# SPDX-License-Identifier: AGPL-3.0-or-later

output "organization_id" {
  value = aws_organizations_organization.this.id
}

output "root_id" {
  value = local.root_id
}

output "ou_ids" {
  value = local.ou_ids
}

output "account_ids" {
  description = "Member account IDs by short name; feed these to the account and logging stages."
  value       = { for k, a in aws_organizations_account.member : k => a.id }
}

output "log_archive_bucket" {
  description = "Name the logging stage gives the organization trail's bucket."
  value       = local.log_archive_bucket
}
