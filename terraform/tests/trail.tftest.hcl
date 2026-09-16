mock_provider "aws" {
  alias = "us_east_1"

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = join("", ["123456", "789012"])
    }
  }

  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:us-east-1:${join("", ["123456", "789012"])}:security-change-alerts"
    }
  }

  mock_resource "aws_sqs_queue" {
    defaults = {
      arn = "arn:aws:sqs:us-east-1:${join("", ["123456", "789012"])}:security-change-alerts-dlq"
    }
  }
}

variables {
  repository            = "nwarila-platform/aws-monitoring-terraform-framework"
  repository_id         = "123456789"
  commit_sha            = "0123456789abcdef0123456789abcdef01234567"
  run_id                = "42"
  environment           = "test"
  alert_emails          = []
  exempt_pipeline_roles = []
  manage_trail          = true
}

# EventBridge receives no CloudTrail events at all without a logging trail, so an account that
# has none gets one here. Both breadth settings are required, not preferred: a security group is
# recorded in the region of the call, and IAM events are global.
run "the_trail_records_what_both_alerts_need" {
  command = plan

  assert {
    condition = alltrue([
      aws_cloudtrail.us_east_1[0].is_multi_region_trail == true,
      aws_cloudtrail.us_east_1[0].include_global_service_events == true,
      aws_cloudtrail.us_east_1[0].enable_log_file_validation == true,
      aws_cloudtrail.us_east_1[0].name == "management-events",
    ])
    error_message = "The trail must cover every region, include global service events, and validate its own log files."
  }
}

# The bucket holds the account's audit record, so the ways it is commonly left open are closed
# explicitly rather than left to account defaults.
run "the_log_bucket_is_closed_and_expires_its_logs" {
  command = plan

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.us_east_1_trail[0].block_public_acls == true,
      aws_s3_bucket_public_access_block.us_east_1_trail[0].block_public_policy == true,
      aws_s3_bucket_public_access_block.us_east_1_trail[0].ignore_public_acls == true,
      aws_s3_bucket_public_access_block.us_east_1_trail[0].restrict_public_buckets == true,
      tolist(aws_s3_bucket_ownership_controls.us_east_1_trail[0].rule)[0].object_ownership == "BucketOwnerEnforced",
    ])
    error_message = "The log bucket must block public access in all four ways and disable ACLs."
  }

  assert {
    condition = alltrue([
      tolist(tolist(aws_s3_bucket_server_side_encryption_configuration.us_east_1_trail[0].rule)[0].apply_server_side_encryption_by_default)[0].sse_algorithm == "AES256",
      aws_s3_bucket_lifecycle_configuration.us_east_1_trail[0].rule[0].expiration[0].days == 365,
      aws_s3_bucket_lifecycle_configuration.us_east_1_trail[0].rule[0].status == "Enabled",
    ])
    error_message = "The log bucket must be encrypted and must expire logs after a year."
  }
}

# CloudTrail refuses to create a trail it cannot write to, and AWS's own policy carries the
# source condition that stops another account's trail writing here.
run "the_bucket_policy_admits_cloudtrail_and_only_this_trail" {
  command = plan

  assert {
    condition = alltrue([
      for statement in jsondecode(aws_s3_bucket_policy.us_east_1_trail[0].policy).Statement : alltrue([
        statement.Principal.Service == "cloudtrail.amazonaws.com",
        statement.Condition.StringEquals["aws:SourceArn"] == "arn:aws:cloudtrail:us-east-1:${data.aws_caller_identity.current.account_id}:trail/management-events",
      ])
    ])
    error_message = "Every statement must admit CloudTrail and condition on this trail's ARN."
  }

  assert {
    condition = [
      for statement in jsondecode(aws_s3_bucket_policy.us_east_1_trail[0].policy).Statement : statement.Action
    ] == ["s3:GetBucketAcl", "s3:PutObject"]
    error_message = "The policy must grant exactly the ACL check and the object write CloudTrail needs."
  }
}

# An account that already has a covering trail must not get a second one: AWS gives one free
# copy of management events per account and bills every copy after it.
run "the_trail_is_not_created_when_the_account_already_has_one" {
  command = plan

  variables {
    manage_trail = false
  }

  assert {
    condition = alltrue([
      length(aws_cloudtrail.us_east_1) == 0,
      length(aws_s3_bucket.us_east_1_trail) == 0,
      length(aws_s3_bucket_policy.us_east_1_trail) == 0,
      length(aws_s3_bucket_lifecycle_configuration.us_east_1_trail) == 0,
    ])
    error_message = "With manage_trail false the framework must create no trail and no bucket."
  }

  assert {
    condition     = length(aws_cloudwatch_event_rule.us_east_1) == 2
    error_message = "The alerts exist either way; only the trail is optional."
  }
}
