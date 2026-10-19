# Runbook: bootstrapping AWS

Builds the organization, accounts, guardrails, audit trail and CI identities.
It runs by hand, once, with management-account credentials; CI never has them.
Everything here is `prevent_destroy`, so a mistaken `destroy` stops at plan.

## Before you start

**Decide the management account.** The design has Moon Technologies LLC own
the AWS accounts, so the business and its liabilities stay separate from
personal accounts. Two ways to get there:

1. **A new management account registered to the LLC** (recommended). Its root
   email is on a domain the LLC controls, billing is the LLC's, and the
   organization stage creates a fresh organization.
2. **Adopt an existing organization.** The account the local AWS CLI is
   signed in to today is already a management account (organization
   `o-inv95zfo2f`, one member, the "taxxess" account, personal root email). If
   that is to become the LLC's, change its contact and billing details to the
   LLC first, then import the organization (step 1 below). Every trusted
   service it already has (`securityhub`, `sso`, `tagpolicies` today) must be
   listed in `aws_service_access_principals`, or Terraform removes them.

Also:

- Root email addresses for prod, staging and log-archive, each unique, on the
  LLC's domain.
- Terraform 1.10 or later (S3-native state locking). Run
  `terraform version`.
- Credentials for an administrator in the management account. IAM Identity
  Center is preferred; avoid long-lived IAM user keys.
- Turn on MFA for the management account's root user and lock it away.

Copy each stage's `terraform.tfvars.example` to a git-ignored `.tfvars` file
and fill it in.

## 1. Organization (local state for now)

```bash
cd infra/bootstrap/organization
printf 'terraform {\n  backend "local" {}\n}\n' > local_override.tf
terraform init
# Adopting an existing organization only:
terraform import aws_organizations_organization.this o-xxxxxxxxxx
terraform plan -var-file=org.tfvars -out=org.plan
terraform apply org.plan
```

Note the outputs: `organization_id`, `account_ids`, `log_archive_bucket`.
New accounts take a few minutes to become usable.

## 2. Management account baseline (local state for now)

```bash
cd ../account
printf 'terraform {\n  backend "local" {}\n}\n' > local_override.tf
terraform init
terraform apply -var-file=management.tfvars -state=management.tfstate
```

with `management.tfvars`:

```hcl
account_id       = "<management id>"
account_name     = "management"
assume_role_name = null
ci_environments  = []
```

This creates `mh-tfstate-<management id>`.

## 3. Move both states into the bucket

```bash
cd ../organization
rm local_override.tf
terraform init -migrate-state \
  -backend-config="bucket=mh-tfstate-<management id>" \
  -backend-config="key=bootstrap/organization.tfstate" \
  -backend-config="region=us-east-1"

cd ../account
rm local_override.tf
mv management.tfstate terraform.tfstate
terraform init -migrate-state \
  -backend-config="bucket=mh-tfstate-<management id>" \
  -backend-config="key=bootstrap/account/management.tfstate" \
  -backend-config="region=us-east-1"
rm -f terraform.tfstate terraform.tfstate.backup
```

Check that `terraform plan -var-file=…` shows no changes in both.

## 4. Member account baselines

The account stage runs once per account, each with its own state key. Switch
between them with `-reconfigure`:

```bash
for acct in log-archive staging prod; do
  terraform init -reconfigure \
    -backend-config="bucket=mh-tfstate-<management id>" \
    -backend-config="key=bootstrap/account/${acct}.tfstate" \
    -backend-config="region=us-east-1"
  terraform apply -var-file="${acct}.tfvars"
done
```

`staging.tfvars` sets `ci_environments = ["staging"]`, `prod.tfvars` sets
`["prod"]`, and `log-archive.tfvars` sets `[]`. Note each account's
`ci_plan_role_arn` and `ci_apply_role_arns`.

## 5. Organization trail

```bash
cd ../logging
terraform init \
  -backend-config="bucket=mh-tfstate-<management id>" \
  -backend-config="key=bootstrap/logging.tfstate" \
  -backend-config="region=us-east-1"
terraform apply -var-file=logging.tfvars
```

## 6. Connect GitHub

In the repository settings:

- Create environments `staging` and `prod`. For `prod`, require a review
  from `drphilibuster` and allow deployments only from `main`.
- Set repository variables `AWS_PLAN_ROLE_ARN_STAGING` and
  `AWS_PLAN_ROLE_ARN_PROD`, and environment variable `AWS_APPLY_ROLE_ARN` in
  each environment, from step 4's outputs.

No secrets are stored: the workflows exchange GitHub's OIDC token for these
roles.

## 7. Verify the guardrails

From the management account, assume `OrganizationAccountAccessRole` in
staging, then:

```bash
aws ec2 describe-vpcs --region sa-east-1      # AccessDenied: outside allowed regions (SCP)
aws ec2 describe-vpcs --region us-east-1      # works
aws cloudtrail stop-logging --name mh-org-trail --region us-east-1  # AccessDenied (SCP)
```

In CloudTrail (management account), confirm that events from every account
are arriving and that `aws cloudtrail validate-logs` passes for the trail.

## Teardown

Everything here is `prevent_destroy` on purpose. Dismantling it deliberately:

1. Remove the `prevent_destroy` lines in a reviewed change.
2. Delete the trail (logging stage). Log objects stay until their Object Lock
   retention ends; governance mode lets a principal with
   `s3:BypassGovernanceRetention` remove them earlier.
3. Close member accounts from Organizations. Closed accounts are suspended for
   90 days before AWS deletes them.
4. State buckets go last, after their stacks are destroyed.

## Costs

Under a few dollars a month at rest:

- the CloudTrail organization trail (the first copy of management events is
  free; data events aren't enabled);
- S3 storage for logs and state;
- five KMS keys: one per account for state, plus the trail key (about $1 each per month).
