# SPDX-FileCopyrightText: 2026 Moon Technologies LLC
# SPDX-License-Identifier: AGPL-3.0-or-later

# The provider-agnostic contract every deployment target builds on. No
# providers and no resources: core validates the hotel's settings and renders
# the names, tags, hostnames and adapter configuration that the cloud modules
# (aws, selfhosted, gcp, azure) consume.
terraform {
  required_version = ">= 1.10"
}
