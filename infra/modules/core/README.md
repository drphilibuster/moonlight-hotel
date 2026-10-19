# infra/modules/core

The provider-agnostic contract every hotel deployment builds on. It has no
providers and creates no resources. It validates the hotel's settings and
renders:

- `name_prefix` and `tags` for every resource;
- `hostnames`, including the per-room and per-show name patterns;
- `task_sizes`, validated, for the cloud module to map to its platform;
- `adapter_config` / `adapter_config_json`: the document the front desk reads
  at start, naming which of the nine adapters and which capabilities the
  target uses, plus limits, retention defaults and feature switches.

Cloud modules (`modules/aws` from M1, then `selfhosted`, `gcp`, `azure`) take
core's outputs as inputs and merge their own endpoints into `adapter_config`.

Tests: `terraform -chdir=infra/modules/core init && terraform -chdir=infra/modules/core test`
