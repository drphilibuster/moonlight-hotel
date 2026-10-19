# SPDX-FileCopyrightText: 2026 Moon Technologies LLC
# SPDX-License-Identifier: AGPL-3.0-or-later

variables {
  environment       = "staging"
  deployment_target = "aws"
  domain            = "moonlighthotel.com"
  home_region       = "us-east-1"
  room_regions      = ["us-east-1", "eu-west-2", "ap-southeast-2"]
}

run "renders_aws_config" {
  command = plan

  assert {
    condition     = output.name_prefix == "mh-staging"
    error_message = "name_prefix should be mh-<environment>"
  }
  assert {
    condition     = output.adapter_config.adapters.task_launcher == "ecs-fargate-stepfunctions"
    error_message = "aws target should use the Fargate + Step Functions launcher"
  }
  assert {
    condition     = length(keys(output.adapter_config.adapters)) == 9
    error_message = "there are exactly nine front-desk adapters"
  }
  assert {
    condition     = output.hostnames.room_pattern == "{room}.rooms.moonlighthotel.com"
    error_message = "room hostnames must be one label under rooms.<domain>"
  }
  assert {
    condition     = output.max_players == 5
    error_message = "rooms are for at most five players"
  }
  assert {
    condition     = jsondecode(output.adapter_config_json).limits.room_idle_minutes == 10
    error_message = "the JSON document should carry the limits"
  }
  assert {
    condition     = output.tags.Owner == "Moon Technologies LLC"
    error_message = "every resource is tagged with its owner"
  }
}

run "every_target_has_all_adapters" {
  command = plan
  variables {
    deployment_target = "azure"
  }
  assert {
    condition     = length(keys(output.adapter_config.adapters)) == 9 && output.adapter_config.capabilities.object_tiering == "blob-access-tiers"
    error_message = "azure must define all nine adapters and its tiering capability"
  }
}

run "rejects_room_regions_without_home" {
  command = plan
  variables {
    room_regions = ["eu-west-2"]
  }
  expect_failures = [var.room_regions]
}

run "rejects_duplicate_regions" {
  command = plan
  variables {
    room_regions = ["us-east-1", "us-east-1"]
  }
  expect_failures = [var.room_regions]
}

run "rejects_unknown_target" {
  command = plan
  variables {
    deployment_target = "heroku"
  }
  expect_failures = [var.deployment_target]
}

run "rejects_bad_domain" {
  command = plan
  variables {
    domain = "Moonlight Hotel"
  }
  expect_failures = [var.domain]
}

run "rejects_missing_task_kind" {
  command = plan
  variables {
    task_sizes = {
      room   = { vcpu = 2, memory_gib = 4 }
      stage  = { vcpu = 4, memory_gib = 8 }
      relay  = { vcpu = 2, memory_gib = 4 }
      lounge = { vcpu = 4, memory_gib = 8 }
    }
  }
  expect_failures = [var.task_sizes]
}

run "rejects_impossible_task_size" {
  command = plan
  variables {
    task_sizes = {
      room   = { vcpu = 3, memory_gib = 4 }
      stage  = { vcpu = 4, memory_gib = 8 }
      relay  = { vcpu = 2, memory_gib = 4 }
      lounge = { vcpu = 4, memory_gib = 8 }
      works  = { vcpu = 2, memory_gib = 4 }
    }
  }
  expect_failures = [var.task_sizes]
}

run "rejects_non_increasing_retention" {
  command = plan
  variables {
    retention = {
      video = { to_infrequent = 90, to_instant_archive = 7, to_archive = 365 }
      audio = { to_infrequent = 182, to_archive = 730 }
    }
  }
  expect_failures = [var.retention]
}
