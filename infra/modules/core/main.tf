# SPDX-FileCopyrightText: 2026 Moon Technologies LLC
# SPDX-License-Identifier: AGPL-3.0-or-later

locals {
  # Design limit, not a setting: rooms are for at most five players.
  max_players = 5

  name_prefix = "mh-${var.environment}"

  tags = merge(var.extra_tags, {
    Project     = "moonlight-hotel"
    Environment = var.environment
    Owner       = "Moon Technologies LLC"
    ManagedBy   = "terraform"
    Source      = "https://github.com/drphilibuster/moonlight-hotel"
  })

  hostnames = {
    lobby      = var.domain
    realtime   = "rt.${var.domain}"
    rooms_zone = "rooms.${var.domain}"
    # A room is <room>.rooms.<domain> (signalling and the hotel protocol, by
    # ALPN) and <room>-turn.rooms.<domain> (TURN over TLS). One label each, so
    # the *.rooms wildcard certificate covers both.
    room_pattern      = "{room}.rooms.${var.domain}"
    room_turn_pattern = "{room}-turn.rooms.${var.domain}"
    relay_pattern     = "relay-{show}.${var.domain}"
    chat_pattern      = "chat-{show}.${var.domain}"
  }

  # Which implementation of each of the nine front-desk interfaces a target uses. The
  # front desk refuses to start if its configuration names an adapter it
  # wasn't built with.
  adapters_by_target = {
    aws = {
      object_store   = "s3"
      task_launcher  = "ecs-fargate-stepfunctions"
      scheduler      = "eventbridge-scheduler"
      email          = "ses"
      dns            = "route53"
      secrets        = "secrets-manager"
      edge_blocklist = "wafv2-cloudfront"
      realtime       = "apigateway-websocket"
      media_signer   = "cloudfront-signed-cookies"
    }
    selfhosted = {
      object_store   = "s3-garage"
      task_launcher  = "docker-engine"
      scheduler      = "frontdesk-cron"
      email          = "smtp"
      dns            = "static-or-rfc2136"
      secrets        = "files-or-openbao"
      edge_blocklist = "caddy-admin"
      realtime       = "native-websocket"
      media_signer   = "frontdesk-forward-auth"
    }
    gcp = {
      object_store   = "gcs"
      task_launcher  = "gce-workflows"
      scheduler      = "cloud-scheduler-and-tasks"
      email          = "smtp"
      dns            = "cloud-dns"
      secrets        = "secret-manager"
      edge_blocklist = "cloud-armor"
      realtime       = "native-websocket"
      media_signer   = "cloud-cdn-signed-cookies"
    }
    azure = {
      object_store   = "azure-blob"
      task_launcher  = "aci-logic-apps"
      scheduler      = "logic-apps-and-service-bus"
      email          = "smtp"
      dns            = "azure-dns"
      secrets        = "key-vault"
      edge_blocklist = "front-door-waf"
      realtime       = "native-websocket"
      media_signer   = "frontdesk-playlist-tokens"
    }
  }

  # What a target can and can't do, for the parts of the hotel that differ by
  # capability rather than by adapter.
  capabilities_by_target = {
    aws = {
      database_auth  = "postgres-iam"
      object_tiering = "s3-storage-classes"
    }
    selfhosted = {
      database_auth  = "postgres-password"
      object_tiering = "none"
    }
    gcp = {
      database_auth  = "postgres-iam"
      object_tiering = "gcs-storage-classes"
    }
    azure = {
      database_auth  = "postgres-entra"
      object_tiering = "blob-access-tiers"
    }
  }

  adapter_config = {
    schema            = 1
    environment       = var.environment
    deployment_target = var.deployment_target
    domain            = var.domain
    home_region       = var.home_region
    room_regions      = var.room_regions
    hostnames         = local.hostnames
    adapters          = local.adapters_by_target[var.deployment_target]
    capabilities      = local.capabilities_by_target[var.deployment_target]
    limits = {
      max_players           = local.max_players
      room_idle_minutes     = var.room_idle_minutes
      max_room_hours        = var.max_room_hours
      presentation_slack_ms = var.presentation_slack_ms
      upload_grant_days     = var.upload_grant_days
      stem_reconcile_hours  = var.stem_reconcile_hours
      ban_ip_days           = var.ban_ip_days
      sign_in_record_days   = var.sign_in_record_days
    }
    retention_defaults = var.retention
    features           = var.features
  }
}
