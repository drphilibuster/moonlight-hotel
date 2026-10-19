# SPDX-FileCopyrightText: 2026 Moon Technologies LLC
# SPDX-License-Identifier: AGPL-3.0-or-later

# Service control policies for every member account. SCPs never apply to the
# management account, which is why nothing runs there but this bootstrap.

locals {
  # Global or us-east-1-only services, exempt from the region restriction.
  global_actions = [
    "account:*", "acm:*", "aws-marketplace:*", "aws-portal:*", "billing:*", "budgets:*",
    "ce:*", "cloudfront:*", "config:*", "cost-optimization-hub:*", "cur:*",
    "ec2:DescribeRegions", "ecr-public:*", "freetier:*", "globalaccelerator:*", "health:*",
    "iam:*", "identitystore:*", "invoicing:*", "kms:*", "networkmanager:*",
    "notifications:*", "organizations:*", "payments:*", "pricing:*", "route53:*",
    "route53domains:*", "s3:GetAccountPublic*", "s3:ListAllMyBuckets",
    "s3:PutAccountPublic*", "shield:*", "sso:*", "sts:*", "support:*", "tax:*",
    "trustedadvisor:*", "waf:*", "wafv2:*", "wellarchitected:*",
  ]

  log_archive_bucket = "mh-org-trail-${aws_organizations_account.member["log-archive"].id}"

  scps = {
    "mh-deny-other-regions" = {
      description = "Member accounts may only use the hotel's regions (global services exempt)."
      targets     = ["security", "workloads"]
      document = {
        Version = "2012-10-17"
        Statement = [{
          Sid       = "DenyOutsideHotelRegions"
          Effect    = "Deny"
          NotAction = local.global_actions
          Resource  = "*"
          Condition = { StringNotEquals = { "aws:RequestedRegion" = var.allowed_regions } }
        }]
      }
    }

    "mh-deny-leave-organization" = {
      description = "Member accounts can't leave the organization."
      targets     = ["security", "workloads"]
      document = {
        Version = "2012-10-17"
        Statement = [{
          Sid      = "DenyLeave"
          Effect   = "Deny"
          Action   = ["organizations:LeaveOrganization"]
          Resource = "*"
        }]
      }
    }

    "mh-protect-audit" = {
      description = "Nobody in a member account can stop or alter CloudTrail, Config, GuardDuty or Access Analyzer."
      targets     = ["security", "workloads"]
      document = {
        Version = "2012-10-17"
        Statement = [{
          Sid    = "ProtectAuditServices"
          Effect = "Deny"
          Action = [
            "cloudtrail:DeleteTrail", "cloudtrail:PutEventSelectors", "cloudtrail:PutInsightSelectors",
            "cloudtrail:StopLogging", "cloudtrail:UpdateTrail",
            "config:DeleteConfigurationRecorder", "config:DeleteDeliveryChannel",
            "config:DeleteRetentionConfiguration", "config:StopConfigurationRecorder",
            "guardduty:DeleteDetector", "guardduty:DeleteMembers",
            "guardduty:DisassociateFromAdministratorAccount", "guardduty:DisassociateFromMasterAccount",
            "guardduty:StopMonitoringMembers", "guardduty:UpdateDetector",
            "access-analyzer:DeleteAnalyzer",
          ]
          Resource = "*"
        }]
      }
    }

    "mh-deny-root-user" = {
      description = "Member-account root users can do nothing; work happens through roles."
      targets     = ["security", "workloads"]
      document = {
        Version = "2012-10-17"
        Statement = [{
          Sid       = "DenyRoot"
          Effect    = "Deny"
          Action    = "*"
          Resource  = "*"
          Condition = { StringLike = { "aws:PrincipalArn" = "arn:aws:iam::*:root" } }
        }]
      }
    }

    "mh-protect-log-archive" = {
      description = "Only the bootstrap role may change the organization trail's bucket or its objects."
      targets     = ["security"]
      document = {
        Version = "2012-10-17"
        Statement = [{
          Sid    = "ProtectTrailBucket"
          Effect = "Deny"
          Action = [
            "s3:DeleteBucket", "s3:DeleteBucketPolicy", "s3:DeleteObject", "s3:DeleteObjectVersion",
            "s3:PutBucketObjectLockConfiguration", "s3:PutBucketPolicy", "s3:PutBucketVersioning",
            "s3:PutLifecycleConfiguration", "s3:PutObjectRetention", "s3:BypassGovernanceRetention",
          ]
          Resource = ["arn:aws:s3:::${local.log_archive_bucket}", "arn:aws:s3:::${local.log_archive_bucket}/*"]
          Condition = {
            ArnNotLike = { "aws:PrincipalArn" = "arn:aws:iam::*:role/OrganizationAccountAccessRole" }
          }
        }]
      }
    }
  }

  scp_attachments = merge([
    for name, p in local.scps : { for t in p.targets : "${name}/${t}" => { policy = name, ou = t } }
  ]...)
}

resource "aws_organizations_policy" "scp" {
  for_each = local.scps

  name        = each.key
  description = each.value.description
  type        = "SERVICE_CONTROL_POLICY"
  content     = jsonencode(each.value.document)
}

resource "aws_organizations_policy_attachment" "scp" {
  for_each = local.scp_attachments

  policy_id = aws_organizations_policy.scp[each.value.policy].id
  target_id = local.ou_ids[each.value.ou]
}
