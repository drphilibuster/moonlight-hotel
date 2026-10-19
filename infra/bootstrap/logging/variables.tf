# SPDX-FileCopyrightText: 2026 Moon Technologies LLC
# SPDX-License-Identifier: AGPL-3.0-or-later

variable "management_account_id" {
  type = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.management_account_id))
    error_message = "management_account_id must be a 12-digit AWS account ID."
  }
}

variable "log_archive_account_id" {
  type = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.log_archive_account_id))
    error_message = "log_archive_account_id must be a 12-digit AWS account ID."
  }
}

variable "organization_id" {
  description = "From the organization stage's output."
  type        = string
  validation {
    condition     = can(regex("^o-[a-z0-9]{10,32}$", var.organization_id))
    error_message = "organization_id looks like o-xxxxxxxxxx."
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "log_retention_days" {
  description = "Days CloudTrail logs are kept before they expire."
  type        = number
  default     = 1095
  validation {
    condition     = var.log_retention_days >= 365
    error_message = "Keep audit logs at least a year."
  }
}

variable "log_infrequent_days" {
  description = "Days before logs move to Glacier Instant Retrieval."
  type        = number
  default     = 90
}

variable "object_lock_days" {
  description = "Governance-mode Object Lock retention on every log object."
  type        = number
  default     = 365
  validation {
    condition     = var.object_lock_days >= 1
    error_message = "object_lock_days must be at least 1."
  }
}
