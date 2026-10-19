# infra/bootstrap

Applied by hand, once, with management-account credentials. CI never runs it.
It builds the accounts, guardrails, audit trail and CI identities that every
other stack depends on.

| Stage | Account(s) | Creates |
| --- | --- | --- |
| [`organization/`](organization/) | management | The organization, the Security and Workloads OUs, the prod, staging and log-archive accounts, and five SCPs |
| [`account/`](account/) | each account in turn | KMS-encrypted state bucket with S3-native locking; in prod and staging, GitHub OIDC, `mh-ci-plan`, `mh-ci-apply-<env>` and the `mh-boundary` permissions boundary |
| [`logging/`](logging/) | management + log-archive | Organization CloudTrail (all regions, log file validation) into an Object-Locked, KMS-encrypted bucket in log-archive |

The order, the local-state first run and the state migration are in
[docs/runbooks/bootstrap.md](../../docs/runbooks/bootstrap.md).

Every stage has `terraform test` suites that run against a mocked AWS
provider, so CI checks them without touching AWS.
