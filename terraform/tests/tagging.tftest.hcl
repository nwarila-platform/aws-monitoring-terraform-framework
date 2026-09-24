mock_provider "aws" {
  alias = "us_east_1"

  # The commercial partition and region, so every ARN the framework writes renders the way a
  # commercial deployment sees it. tests/portability.tftest.hcl renders the GovCloud case.
  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }

  # IAM's answer for the deploying session's role.
  mock_data "aws_iam_session_context" {
    defaults = {
      issuer_arn = "arn:aws:iam::${join("", ["123456", "789012"])}:role/example-deploy-role"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = join("", ["123456", "789012"])
      arn        = "arn:aws:sts::${join("", ["123456", "789012"])}:assumed-role/example-deploy-role/aws-deploy-42"
    }
  }
}

variables {
  repository            = "example-org/aws-monitoring"
  repository_id         = "123456789"
  commit_sha            = "0123456789abcdef0123456789abcdef01234567"
  run_id                = "42"
  environment           = "test"
  manage_trail          = false
  exempt_pipeline_roles = []
  alert_emails          = []
  alert_key_alias       = null
}

# What provider default_tags carries, pinned as an exact key set. These six are the only keys
# whose value is identical on every resource.
run "identity_tags_carry_exactly_the_six_uniform_keys" {
  command = plan

  assert {
    condition = local.identity_tags == {
      CommitSha    = "0123456789abcdef0123456789abcdef01234567"
      Environment  = "test"
      ManagedBy    = "Terraform"
      Repository   = "example-org/aws-monitoring"
      RepositoryId = "123456789"
      RunId        = "42"
    }
    error_message = "default_tags must carry exactly the six identity keys whose value is uniform across every resource."
  }
}

# Identity is written into each tag map rather than left to default_tags alone, so the
# resource's own tags are the record.
run "every_taggable_resource_carries_identity_and_its_name" {
  command = plan

  assert {
    condition = alltrue(concat(
      [
        aws_kms_key.us_east_1["security-change-alerts"].tags == tomap(merge(local.identity_tags, { Name = "security-change-alerts" })),
        aws_sns_topic.us_east_1.tags == tomap(merge(local.identity_tags, { Name = "security-change-alerts" })),
        aws_sns_topic.us_east_1_health.tags == tomap(merge(local.identity_tags, { Name = "security-change-alerts-health" })),
        aws_sqs_queue.us_east_1_dlq.tags == tomap(merge(local.identity_tags, { Name = "security-change-alerts-dlq" })),
        aws_cloudwatch_metric_alarm.us_east_1_undelivered.tags == tomap(merge(local.identity_tags, { Name = "security-change-alerts-undelivered" })),
        aws_cloudwatch_metric_alarm.us_east_1_notification_failures.tags == tomap(merge(local.identity_tags, { Name = "security-change-alerts-notification-failures" })),
      ],
      [
        for key, rule in aws_cloudwatch_event_rule.us_east_1 :
        rule.tags == tomap(merge(local.identity_tags, { Name = "security-change-alerts-${key}" }))
      ],
      [
        for key, alarm in aws_cloudwatch_metric_alarm.us_east_1_failed_invocations :
        alarm.tags == tomap(merge(local.identity_tags, { Name = "security-change-alerts-${key}-failed-invocations" }))
      ],
    ))
    error_message = "The key, both topics, the queue, each rule and each alarm must carry all six identity keys plus their own Name."
  }
}

# The trail and its bucket exist only when asked for, so their tags are checked in that mode.
run "the_trail_and_its_bucket_carry_identity_and_their_names" {
  command = plan

  variables {
    manage_trail = true
  }

  assert {
    condition = alltrue([
      aws_cloudtrail.us_east_1["management-events"].tags == tomap(merge(local.identity_tags, { Name = "management-events" })),
      aws_s3_bucket.us_east_1_trail["management-events"].tags == tomap(merge(local.identity_tags, { Name = "${data.aws_caller_identity.current.account_id}-cloudtrail" })),
    ])
    error_message = "The trail and its bucket must carry all six identity keys plus their own Name."
  }
}

run "accepts_prod_environment" {
  command = plan

  variables {
    environment  = "prod"
    alert_emails = ["security@example.com"]
  }

  assert {
    condition     = aws_sns_topic.us_east_1.tags["Environment"] == "prod"
    error_message = "A supported environment value must reach the Environment tag verbatim."
  }
}
