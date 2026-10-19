# SPDX-FileCopyrightText: 2026 Moon Technologies LLC
# SPDX-License-Identifier: AGPL-3.0-or-later

variable "management_account_id" {
  description = "The organization's management account. Owned by Moon Technologies LLC."
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.management_account_id))
    error_message = "management_account_id must be a 12-digit AWS account ID."
  }
}

variable "region" {
  description = "Region for the organization's regional resources (the org trail's home)."
  type        = string
  default     = "us-east-1"
}

variable "allowed_regions" {
  description = <<-EOT
    Regions member accounts may use: the hotel's home region plus every room
    region. Global services (IAM, CloudFront, Route 53, WAF and the like) are
    exempt. Add a region here before adding it to room_regions.
  EOT
  type        = list(string)
  validation {
    condition     = length(var.allowed_regions) > 0 && contains(var.allowed_regions, "us-east-1")
    error_message = "allowed_regions must include us-east-1, where CloudFront certificates and WAF for CloudFront live."
  }
}

variable "accounts" {
  description = <<-EOT
    Member accounts, keyed by short name. Each needs a unique root email
    address on a domain the LLC controls. ou is "security" or "workloads".
  EOT
  type = map(object({
    name  = string
    email = string
    ou    = string
  }))
  validation {
    condition     = alltrue([for a in values(var.accounts) : contains(["security", "workloads"], a.ou)])
    error_message = "Each account's ou must be security or workloads."
  }
  validation {
    condition     = alltrue([for k in ["prod", "staging", "log-archive"] : contains(keys(var.accounts), k)])
    error_message = "accounts must include prod, staging and log-archive."
  }
  validation {
    condition     = length(distinct([for a in values(var.accounts) : lower(a.email)])) == length(var.accounts)
    error_message = "Every account needs its own root email address."
  }
}

variable "aws_service_access_principals" {
  description = <<-EOT
    Services with trusted access to the organization. CloudTrail is required
    for the organization trail. When adopting an existing organization, list
    every principal it already trusts, or Terraform will remove them.
  EOT
  type        = list(string)
  default     = ["cloudtrail.amazonaws.com", "sso.amazonaws.com"]
  validation {
    condition     = contains(var.aws_service_access_principals, "cloudtrail.amazonaws.com")
    error_message = "cloudtrail.amazonaws.com must have trusted access for the organization trail."
  }
}

variable "enabled_policy_types" {
  description = "Organization policy types to enable. SCPs are required."
  type        = list(string)
  default     = ["SERVICE_CONTROL_POLICY"]
  validation {
    condition     = contains(var.enabled_policy_types, "SERVICE_CONTROL_POLICY")
    error_message = "SERVICE_CONTROL_POLICY must be enabled."
  }
}
