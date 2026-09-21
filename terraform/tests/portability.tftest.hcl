# The framework writes a few ARNs itself: the key policy's account root, the deploying role, the
# trail, and its bucket. They must come from the provider's partition and region, so that
# providers.tf is the only file that changes between a commercial and a GovCloud account. This suite
# renders every one of them under GovCloud and checks that nothing commercial leaks through.

mock_provider "aws" {
  alias = "us_east_1"

  mock_data "aws_partition" {
    defaults = {
      partition  = "aws-us-gov"
      dns_suffix = "amazonaws.com"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "us-gov-west-1"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = join("", ["123456", "789012"])
      arn        = "arn:aws-us-gov:sts::${join("", ["123456", "789012"])}:assumed-role/example-deploy-role/build-7"
    }
  }

  # Computed ARNs as GovCloud returns them, so every policy and target renders exactly as it would
  # there after an apply.
  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws-us-gov:sns:us-gov-west-1:${join("", ["123456", "789012"])}:security-change-alerts"
    }
  }

  mock_resource "aws_sqs_queue" {
    defaults = {
      arn = "arn:aws-us-gov:sqs:us-gov-west-1:${join("", ["123456", "789012"])}:security-change-alerts-dlq"
      id  = "https://sqs.us-gov-west-1.amazonaws.com/${join("", ["123456", "789012"])}/security-change-alerts-dlq"
    }
  }

  mock_resource "aws_cloudwatch_event_rule" {
    defaults = {
      arn = "arn:aws-us-gov:events:us-gov-west-1:${join("", ["123456", "789012"])}:rule/security-change-alerts"
    }
  }
}

variables {
  repository    = "infrastructure/aws/monitoring"
  repository_id = "4242"
  commit_sha    = "0123456789abcdef0123456789abcdef01234567"
  run_id        = "7"
  environment   = "prod"
  alert_emails  = ["security@example.com"]
}

run "every_arn_the_framework_writes_takes_the_providers_partition_and_region" {
  command = plan

  variables {
    manage_trail = true
  }

  assert {
    condition = alltrue([
      contains([for s in jsondecode(aws_kms_key.us_east_1.policy).Statement : s.Principal.AWS if s.Sid == "AccountAdministersTheKey"],
      "arn:aws-us-gov:iam::123456789012:root"),
      contains([for s in jsondecode(aws_kms_key.us_east_1.policy).Statement : s.Principal.AWS if s.Sid == "DeployRoleAdministersTheKey"],
      "arn:aws-us-gov:iam::123456789012:role/example-deploy-role"),
    ])
    error_message = "The key policy must name the account root and the deploying role in the provider's partition."
  }

  assert {
    condition = alltrue([
      for s in jsondecode(aws_s3_bucket_policy.us_east_1_trail[0].policy).Statement : alltrue([
        s.Condition.StringEquals["aws:SourceArn"] == "arn:aws-us-gov:cloudtrail:us-gov-west-1:123456789012:trail/management-events",
        startswith(s.Resource, "arn:aws-us-gov:s3:::123456789012-cloudtrail"),
      ])
    ])
    error_message = "The trail bucket policy must name the trail and the bucket in the provider's partition and region."
  }

  assert {
    condition = alltrue([
      for document in [aws_kms_key.us_east_1.policy, aws_s3_bucket_policy.us_east_1_trail[0].policy] :
      !strcontains(document, "arn:aws:")
    ])
    error_message = "Neither the key policy nor the trail bucket policy may name the commercial partition."
  }
}

# The property that matters, checked after a mocked apply so that computed ARNs are filled in: no
# policy, target, or output the framework produces names the commercial partition. The trail is
# left out here because its resources carry prevent_destroy, which a test cannot tear down; the
# plan-only run above checks its bucket policy.
run "nothing_the_framework_produces_names_the_commercial_partition" {
  command = apply

  assert {
    condition = alltrue([
      for document in concat(
        [
          aws_kms_key.us_east_1.policy,
          aws_sns_topic_policy.us_east_1.policy,
          aws_sns_topic_policy.us_east_1_health.policy,
          aws_sqs_queue_policy.us_east_1_dlq.policy,
          jsonencode(output.alert_rules),
          output.alert_topic_arn,
          output.health_topic_arn,
        ],
        [for target in aws_cloudwatch_event_target.us_east_1 : target.arn],
        [for target in aws_cloudwatch_event_target.us_east_1 : target.dead_letter_config[0].arn],
        [for alarm in aws_cloudwatch_metric_alarm.us_east_1_failed_invocations : jsonencode(alarm.alarm_actions)],
      ) : !strcontains(document, "arn:aws:")
    ])
    error_message = "A GovCloud deployment must not produce a single commercial-partition ARN."
  }
}

# IAM events are recorded only in the partition's global-service region. A provider pointed
# anywhere else would create an IAM rule that never fires, so the plan must refuse it.
run "a_region_that_cannot_see_iam_events_is_refused" {
  command = plan

  override_data {
    target = data.aws_region.current
    values = {
      region = "us-gov-east-1"
    }
  }

  expect_failures = [aws_cloudwatch_event_rule.us_east_1]
}

# manage_trail and exempt_pipeline_roles are omitted here, so this run sees their defaults: the
# values a new account takes when its value file says nothing. Neither may create a trail or
# silence anyone.
run "omitted_values_fall_to_the_safe_defaults" {
  command = plan

  assert {
    condition     = length(aws_cloudtrail.us_east_1) == 0 && length(aws_s3_bucket.us_east_1_trail) == 0
    error_message = "By default the framework must not create a trail, which could bill management events twice."
  }

  assert {
    condition     = !can(jsondecode(aws_cloudwatch_event_rule.us_east_1["security-group"].event_pattern).detail["$or"])
    error_message = "By default nobody is exempt from the security-group alert."
  }
}
