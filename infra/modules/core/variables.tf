# SPDX-FileCopyrightText: 2026 Moon Technologies LLC
# SPDX-License-Identifier: AGPL-3.0-or-later

variable "environment" {
  description = "Deployment name, e.g. staging or prod. Lower case, used in every resource name."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,15}$", var.environment))
    error_message = "environment must be 2-16 characters: lower-case letters, digits and hyphens, starting with a letter."
  }
}

variable "deployment_target" {
  description = "Which cloud module consumes this: aws, selfhosted, gcp or azure."
  type        = string
  validation {
    condition     = contains(["aws", "selfhosted", "gcp", "azure"], var.deployment_target)
    error_message = "deployment_target must be one of aws, selfhosted, gcp, azure."
  }
}

variable "domain" {
  description = "The hotel's apex domain, e.g. moonlighthotel.com. The lobby is served here; rooms live under rooms.<domain>."
  type        = string
  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", var.domain))
    error_message = "domain must be a lower-case DNS name such as moonlighthotel.com."
  }
}

variable "home_region" {
  description = "Region for the control plane: front desk, database, vault, edge and the default relay."
  type        = string
  validation {
    condition     = can(regex("^[a-z]{2,}(-[a-z0-9]+)+$", var.home_region))
    error_message = "home_region must be a region identifier such as us-east-1, europe-west2 or uksouth."
  }
}

variable "room_regions" {
  description = "Regions rooms can launch in. Must include home_region. Hosts pick one; the lobby suggests the nearest."
  type        = list(string)
  validation {
    condition     = length(var.room_regions) > 0 && length(distinct(var.room_regions)) == length(var.room_regions)
    error_message = "room_regions must be a non-empty list with no duplicates."
  }
  validation {
    condition     = contains(var.room_regions, var.home_region)
    error_message = "room_regions must include home_region."
  }
}

variable "task_sizes" {
  description = <<-EOT
    vCPU and memory for each kind of on-demand task. Cloud modules map these to
    their own sizes and reject combinations their platform can't run.
  EOT
  type = map(object({
    vcpu       = number
    memory_gib = number
  }))
  default = {
    room   = { vcpu = 2, memory_gib = 4 }
    stage  = { vcpu = 4, memory_gib = 8 }
    relay  = { vcpu = 2, memory_gib = 4 }
    lounge = { vcpu = 4, memory_gib = 8 }
    works  = { vcpu = 2, memory_gib = 4 }
  }
  validation {
    condition = (
      length(setsubtract(["room", "stage", "relay", "lounge", "works"], keys(var.task_sizes))) == 0 &&
      length(setsubtract(keys(var.task_sizes), ["room", "stage", "relay", "lounge", "works"])) == 0
    )
    error_message = "task_sizes must define exactly room, stage, relay, lounge and works."
  }
  validation {
    condition = alltrue([
      for s in values(var.task_sizes) :
      contains([0.25, 0.5, 1, 2, 4, 8, 16], s.vcpu) && s.memory_gib >= s.vcpu && s.memory_gib <= s.vcpu * 8
    ])
    error_message = "Each size needs vcpu in {0.25, 0.5, 1, 2, 4, 8, 16} and memory_gib between 1x and 8x its vcpu."
  }
}

variable "room_idle_minutes" {
  description = "Minutes with no players connected before the housekeeper checks a room out."
  type        = number
  default     = 10
  validation {
    condition     = var.room_idle_minutes >= 1 && var.room_idle_minutes <= 120 && floor(var.room_idle_minutes) == var.room_idle_minutes
    error_message = "room_idle_minutes must be a whole number from 1 to 120."
  }
}

variable "max_room_hours" {
  description = "Hard ceiling on a room's life, after which it checks out regardless of activity."
  type        = number
  default     = 12
  validation {
    condition     = var.max_room_hours >= 1 && var.max_room_hours <= 72
    error_message = "max_room_hours must be from 1 to 72."
  }
}

variable "presentation_slack_ms" {
  description = "Default D: fixed slack added to the broadcast's presentation clock, at least the VJ round trip."
  type        = number
  default     = 500
  validation {
    condition     = var.presentation_slack_ms >= 200 && var.presentation_slack_ms <= 2000
    error_message = "presentation_slack_ms must be from 200 to 2000."
  }
}

variable "upload_grant_days" {
  description = "Days after checkout that a player's lossless upload grant stays valid, so queued intervals still reach the vault."
  type        = number
  default     = 30
  validation {
    condition     = var.upload_grant_days >= 1 && var.upload_grant_days <= 90
    error_message = "upload_grant_days must be from 1 to 90."
  }
}

variable "stem_reconcile_hours" {
  description = "Hours after checkout before stems are consolidated, unless every upload grant drains sooner."
  type        = number
  default     = 24
  validation {
    condition     = var.stem_reconcile_hours >= 1 && var.stem_reconcile_hours <= 168
    error_message = "stem_reconcile_hours must be from 1 to 168."
  }
}

variable "retention" {
  description = <<-EOT
    Days a master can go unchosen before the night porter moves it down a tier.
    These seed the database settings the night porter reads; admins can change
    them there without a deploy.
  EOT
  type = object({
    video = object({ to_infrequent = number, to_instant_archive = number, to_archive = number })
    audio = object({ to_infrequent = number, to_archive = number })
  })
  default = {
    video = { to_infrequent = 7, to_instant_archive = 90, to_archive = 365 }
    audio = { to_infrequent = 182, to_archive = 730 }
  }
  validation {
    condition = (
      var.retention.video.to_infrequent > 0 &&
      var.retention.video.to_instant_archive > var.retention.video.to_infrequent &&
      var.retention.video.to_archive > var.retention.video.to_instant_archive &&
      var.retention.audio.to_infrequent > 0 &&
      var.retention.audio.to_archive > var.retention.audio.to_infrequent
    )
    error_message = "Retention thresholds must be positive and strictly increasing within video and within audio."
  }
}

variable "ban_ip_days" {
  description = "Default length of an IP-layer ban; renewable."
  type        = number
  default     = 90
}

variable "sign_in_record_days" {
  description = "Days sign-in IPs and device IDs are kept for accounts that aren't banned (the privacy policy states this)."
  type        = number
  default     = 90
}

variable "features" {
  description = "Switches for parts of the hotel an operator may not run. Off means absent, not degraded."
  type = object({
    ticketing          = bool
    audience_chat      = bool
    lossless_broadcast = bool
  })
  default = {
    ticketing          = false
    audience_chat      = true
    lossless_broadcast = true
  }
}

variable "extra_tags" {
  description = "Tags added to every resource, on top of the hotel's own."
  type        = map(string)
  default     = {}
}
