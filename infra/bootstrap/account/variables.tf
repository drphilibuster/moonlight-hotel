# SPDX-FileCopyrightText: 2026 Moon Technologies LLC
# SPDX-License-Identifier: AGPL-3.0-or-later

variable "account_id" {
  description = "The account this baseline is applied to."
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "account_name" {
  description = "Short name: management, prod, staging or log-archive."
  type        = string
  validation {
    condition     = contains(["management", "prod", "staging", "log-archive"], var.account_name)
    error_message = "account_name must be management, prod, staging or log-archive."
  }
}

variable "assume_role_name" {
  description = "Role to assume in the account, or null to use the caller's credentials (management only)."
  type        = string
  default     = "OrganizationAccountAccessRole"
}

variable "region" {
  description = "Region for the state bucket and its key."
  type        = string
  default     = "us-east-1"
}

variable "github_repository" {
  description = "owner/name of the repository whose workflows may assume the CI roles."
  type        = string
  default     = "drphilibuster/moonlight-hotel"
  validation {
    condition     = can(regex("^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$", var.github_repository))
    error_message = "github_repository must be owner/name."
  }
}

variable "ci_environments" {
  description = <<-EOT
    GitHub environments that may apply to this account, e.g. ["prod"]. Each
    gets an mh-ci-apply-<env> role trusted only for workflow jobs running in
    that environment. Empty for management and log-archive, which CI never
    touches.
  EOT
  type        = list(string)
  default     = []
  validation {
    condition     = alltrue([for e in var.ci_environments : can(regex("^[a-z][a-z0-9-]{1,15}$", e))])
    error_message = "Environment names must be lower case, 2-16 characters."
  }
}

variable "state_noncurrent_days" {
  description = "Days to keep superseded state versions."
  type        = number
  default     = 90
}
