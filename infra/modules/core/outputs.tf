# SPDX-FileCopyrightText: 2026 Moon Technologies LLC
# SPDX-License-Identifier: AGPL-3.0-or-later

output "name_prefix" {
  description = "Prefix for every resource name in this deployment."
  value       = local.name_prefix
}

output "tags" {
  description = "Tags to apply to every resource."
  value       = local.tags
}

output "hostnames" {
  description = "The hotel's hostnames and per-room/per-show name patterns."
  value       = local.hostnames
}

output "home_region" {
  value = var.home_region
}

output "room_regions" {
  value = var.room_regions
}

output "task_sizes" {
  description = "Validated vCPU and memory per task kind."
  value       = var.task_sizes
}

output "max_players" {
  description = "Players per room (design limit)."
  value       = local.max_players
}

output "adapter_config" {
  description = "The front desk's provider-agnostic configuration. Cloud modules merge their endpoints into it."
  value       = local.adapter_config
}

output "adapter_config_json" {
  description = "adapter_config as the JSON document the front desk reads at start."
  value       = jsonencode(local.adapter_config)
}
