# SPDX-FileCopyrightText: 2026 Moon Technologies LLC
# SPDX-License-Identifier: AGPL-3.0-or-later

output "state_bucket" {
  description = "Backend bucket for this account's stacks."
  value       = aws_s3_bucket.state.bucket
}

output "state_kms_key_arn" {
  value = aws_kms_key.state.arn
}

output "ci_plan_role_arn" {
  description = "Set as the AWS_PLAN_ROLE_ARN variable for the repository."
  value       = try(aws_iam_role.ci_plan[0].arn, null)
}

output "ci_apply_role_arns" {
  description = "Set each as AWS_APPLY_ROLE_ARN in the matching GitHub environment."
  value       = { for env, r in aws_iam_role.ci_apply : env => r.arn }
}

output "permissions_boundary_arn" {
  description = "Every role the hotel's stacks create must use this boundary."
  value       = try(aws_iam_policy.boundary[0].arn, null)
}
