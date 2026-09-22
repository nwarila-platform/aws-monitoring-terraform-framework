# Managed resources. Consumes the shaped maps from locals.tf.


#region ------ [ aws_kms_key ] ----------------------------------------------------------------- #

#region ------ [ aws_kms_key - us-east-1 ] ----------------------------------------------------- #

resource "aws_kms_key" "us_east_1" {

  provider = aws.us_east_1

  # Define the Alert Topic Key Properties
  deletion_window_in_days = 30
  description             = "Encrypts the ${local.alert_name} SNS topic at rest."
  enable_key_rotation     = true
  policy                  = local.alert_key_policy
  tags                    = local.alert_tags

}

#endregion --- [ aws_kms_key - us-east-1 ] ----------------------------------------------------- #

#endregion --- [ aws_kms_key ] ----------------------------------------------------------------- #


#region ------ [ aws_kms_alias ] --------------------------------------------------------------- #

#region ------ [ aws_kms_alias - us-east-1 ] --------------------------------------------------- #

resource "aws_kms_alias" "us_east_1" {

  provider = aws.us_east_1

  # Define the Alert Topic Key Alias Properties
  name          = "alias/${local.alert_name}"
  target_key_id = aws_kms_key.us_east_1.key_id

}

#endregion --- [ aws_kms_alias - us-east-1 ] --------------------------------------------------- #

#endregion --- [ aws_kms_alias ] --------------------------------------------------------------- #


#region ------ [ aws_sns_topic ] --------------------------------------------------------------- #

#region ------ [ aws_sns_topic - us-east-1 ] --------------------------------------------------- #

resource "aws_sns_topic" "us_east_1" {

  provider = aws.us_east_1

  # Define the Alert Topic Properties. The display name is the sender name recipients see.
  # EventBridge sets no per-message subject, so every email arrives under SNS's fixed subject and
  # the headline is the body's first line.
  display_name      = "AWS security change alerts"
  kms_master_key_id = aws_kms_key.us_east_1.key_id
  name              = local.alert_name
  tags              = local.alert_tags

}

#endregion --- [ aws_sns_topic - us-east-1 ] --------------------------------------------------- #

#endregion --- [ aws_sns_topic ] --------------------------------------------------------------- #


#region ------ [ aws_sns_topic_policy ] -------------------------------------------------------- #

#region ------ [ aws_sns_topic_policy - us-east-1 ] -------------------------------------------- #

resource "aws_sns_topic_policy" "us_east_1" {

  provider = aws.us_east_1

  # Define the Alert Topic Policy Properties
  arn    = aws_sns_topic.us_east_1.arn
  policy = local.alert_topic_policy

}

#endregion --- [ aws_sns_topic_policy - us-east-1 ] -------------------------------------------- #

#endregion --- [ aws_sns_topic_policy ] -------------------------------------------------------- #


#region ------ [ aws_sns_topic_subscription ] -------------------------------------------------- #

#region ------ [ aws_sns_topic_subscription - us-east-1 ] -------------------------------------- #

resource "aws_sns_topic_subscription" "us_east_1" {

  # Iterate through all Alert Recipients in the US-East-1 region.
  provider = aws.us_east_1
  for_each = local.alert_recipients

  # Define the Alert Subscription Properties. An email subscription is created pending and stays
  # so until the recipient confirms it; Terraform cannot confirm on their behalf.
  endpoint  = each.value
  protocol  = "email"
  topic_arn = aws_sns_topic.us_east_1.arn

}

#endregion --- [ aws_sns_topic_subscription - us-east-1 ] -------------------------------------- #

#endregion --- [ aws_sns_topic_subscription ] -------------------------------------------------- #


#region ------ [ aws_sns_topic.health ] -------------------------------------------------------- #

#region ------ [ aws_sns_topic.health - us-east-1 ] -------------------------------------------- #

resource "aws_sns_topic" "us_east_1_health" {

  provider = aws.us_east_1

  # Define the Health Topic Properties
  display_name      = "AWS security alert channel health"
  kms_master_key_id = aws_kms_key.us_east_1.key_id
  name              = local.health_name
  tags              = local.health_tags

}

#endregion --- [ aws_sns_topic.health - us-east-1 ] -------------------------------------------- #

#endregion --- [ aws_sns_topic.health ] -------------------------------------------------------- #


#region ------ [ aws_sns_topic_policy.health ] ------------------------------------------------- #

#region ------ [ aws_sns_topic_policy.health - us-east-1 ] ------------------------------------- #

resource "aws_sns_topic_policy" "us_east_1_health" {

  provider = aws.us_east_1

  # Define the Health Topic Policy Properties
  arn    = aws_sns_topic.us_east_1_health.arn
  policy = local.health_topic_policy

}

#endregion --- [ aws_sns_topic_policy.health - us-east-1 ] ------------------------------------- #

#endregion --- [ aws_sns_topic_policy.health ] ------------------------------------------------- #


#region ------ [ aws_sns_topic_subscription.health ] ------------------------------------------- #

#region ------ [ aws_sns_topic_subscription.health - us-east-1 ] ------------------------------- #

resource "aws_sns_topic_subscription" "us_east_1_health" {

  # Iterate through all Alert Recipients in the US-East-1 region. The people who receive the
  # alerts are the people who must hear that the alerts stopped.
  provider = aws.us_east_1
  for_each = local.alert_recipients

  # Define the Health Subscription Properties
  endpoint  = each.value
  protocol  = "email"
  topic_arn = aws_sns_topic.us_east_1_health.arn

}

#endregion --- [ aws_sns_topic_subscription.health - us-east-1 ] ------------------------------- #

#endregion --- [ aws_sns_topic_subscription.health ] ------------------------------------------- #


#region ------ [ aws_sqs_queue ] --------------------------------------------------------------- #

#region ------ [ aws_sqs_queue - us-east-1 ] --------------------------------------------------- #

resource "aws_sqs_queue" "us_east_1_dlq" {

  provider = aws.us_east_1

  # Define the Dead-Letter Queue Properties. Fourteen days is the SQS maximum and the point of
  # the queue: an alert that could not be delivered is kept until somebody reads it, rather than
  # dropped when retries run out.
  message_retention_seconds = 1209600
  name                      = local.dlq_name
  # SQS-managed encryption rather than the alert key: the queue holds the same event the email
  # carries, and a customer key here would need its own grant for no further protection.
  sqs_managed_sse_enabled = true
  tags                    = local.dlq_tags

}

#endregion --- [ aws_sqs_queue - us-east-1 ] --------------------------------------------------- #

#endregion --- [ aws_sqs_queue ] --------------------------------------------------------------- #


#region ------ [ aws_sqs_queue_policy ] -------------------------------------------------------- #

#region ------ [ aws_sqs_queue_policy - us-east-1 ] -------------------------------------------- #

resource "aws_sqs_queue_policy" "us_east_1_dlq" {

  provider = aws.us_east_1

  # Define the Dead-Letter Queue Policy Properties
  policy    = local.dlq_policy
  queue_url = aws_sqs_queue.us_east_1_dlq.id

}

#endregion --- [ aws_sqs_queue_policy - us-east-1 ] -------------------------------------------- #

#endregion --- [ aws_sqs_queue_policy ] -------------------------------------------------------- #


#region ------ [ aws_cloudwatch_event_rule ] --------------------------------------------------- #

#region ------ [ aws_cloudwatch_event_rule - us-east-1 ] --------------------------------------- #

resource "aws_cloudwatch_event_rule" "us_east_1" {

  # Iterate through all Change Alerts in the US-East-1 region.
  provider = aws.us_east_1
  for_each = local.change_alerts

  # Define the Event Rule Properties. CloudTrail delivers only to the default bus, and ENABLED
  # is the state that matches write management events.
  description    = each.value.description
  event_bus_name = "default"
  event_pattern  = local.event_patterns[each.key]
  name           = local.rule_names[each.key]
  state          = "ENABLED"
  tags           = local.rule_tags[each.key]

  lifecycle {
    precondition {
      condition = (
        each.value.source != "aws.iam" ||
        lookup(local.global_service_regions, data.aws_partition.current.partition, "") == data.aws_region.current.region
      )
      error_message = (
        contains(keys(local.global_service_regions), data.aws_partition.current.partition)
        ? format(
          "IAM events in partition %s are recorded only in %s, but the provider targets %s; the IAM alert would never fire. Point providers.tf at %s.",
          data.aws_partition.current.partition,
          local.global_service_regions[data.aws_partition.current.partition],
          data.aws_region.current.region,
          local.global_service_regions[data.aws_partition.current.partition],
        )
        : format(
          "Partition %s is not supported: the region where it records IAM events is unknown, so the IAM alert might never fire. Add it to local.global_service_regions from AWS documentation.",
          data.aws_partition.current.partition,
        )
      )
    }
  }

}

#endregion --- [ aws_cloudwatch_event_rule - us-east-1 ] --------------------------------------- #

#endregion --- [ aws_cloudwatch_event_rule ] --------------------------------------------------- #


#region ------ [ aws_cloudwatch_event_target ] ------------------------------------------------- #

#region ------ [ aws_cloudwatch_event_target - us-east-1 ] ------------------------------------- #

resource "aws_cloudwatch_event_target" "us_east_1" {

  # Iterate through all Change Alerts in the US-East-1 region.
  provider = aws.us_east_1
  for_each = local.change_alerts

  # Define the Event Target Properties
  arn            = aws_sns_topic.us_east_1.arn
  event_bus_name = "default"
  rule           = aws_cloudwatch_event_rule.us_east_1[each.key].name
  target_id      = local.alert_name

  dead_letter_config {
    arn = aws_sqs_queue.us_east_1_dlq.arn
  }

  input_transformer {
    input_paths    = local.message_paths
    input_template = local.message_templates[each.key]
  }

  retry_policy {
    # A security alert that arrives a day late has already failed. Giving up after an hour puts
    # the event in the queue and the alarm in front of a person while it still matters, rather
    # than retrying quietly for the AWS default of 24 hours.
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 20
  }

}

#endregion --- [ aws_cloudwatch_event_target - us-east-1 ] ------------------------------------- #

#endregion --- [ aws_cloudwatch_event_target ] ------------------------------------------------- #


#region ------ [ aws_cloudwatch_metric_alarm ] ------------------------------------------------- #

#region ------ [ aws_cloudwatch_metric_alarm.failed_invocations - us-east-1 ] ------------------ #

resource "aws_cloudwatch_metric_alarm" "us_east_1_failed_invocations" {

  # Iterate through all Change Alerts in the US-East-1 region.
  provider = aws.us_east_1
  for_each = local.change_alerts

  # Define the Failed-Invocation Alarm Properties. EventBridge publishes FailedInvocations only
  # when it is non-zero, so missing data is the healthy state and must not read as alarm.
  alarm_actions       = [aws_sns_topic.us_east_1_health.arn]
  alarm_description   = "EventBridge could not deliver a ${each.key} alert to the topic."
  alarm_name          = local.failed_invocation_alarm_names[each.key]
  comparison_operator = "GreaterThanOrEqualToThreshold"
  datapoints_to_alarm = 1
  dimensions          = { RuleName = aws_cloudwatch_event_rule.us_east_1[each.key].name }
  evaluation_periods  = 1
  metric_name         = "FailedInvocations"
  namespace           = "AWS/Events"
  ok_actions          = [aws_sns_topic.us_east_1_health.arn]
  period              = 300
  statistic           = "Sum"
  tags                = local.failed_invocation_alarm_tags[each.key]
  threshold           = 1
  treat_missing_data  = "notBreaching"

}

#endregion --- [ aws_cloudwatch_metric_alarm.failed_invocations - us-east-1 ] ------------------ #

#region ------ [ aws_cloudwatch_metric_alarm.undelivered - us-east-1 ] ------------------------- #

resource "aws_cloudwatch_metric_alarm" "us_east_1_undelivered" {

  provider = aws.us_east_1

  # Define the Undelivered-Alert Alarm Properties. A message in the queue is an alert that was
  # never emailed; the queue holds it for fourteen days so it can still be read.
  alarm_actions       = [aws_sns_topic.us_east_1_health.arn]
  alarm_description   = "A security change alert was never delivered and is waiting in ${local.dlq_name}."
  alarm_name          = local.undelivered_alarm_name
  comparison_operator = "GreaterThanOrEqualToThreshold"
  datapoints_to_alarm = 1
  dimensions          = { QueueName = aws_sqs_queue.us_east_1_dlq.name }
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  ok_actions          = [aws_sns_topic.us_east_1_health.arn]
  period              = 300
  statistic           = "Maximum"
  tags                = local.undelivered_alarm_tags
  threshold           = 1
  treat_missing_data  = "notBreaching"

}

#endregion --- [ aws_cloudwatch_metric_alarm.undelivered - us-east-1 ] ------------------------- #

#region ------ [ aws_cloudwatch_metric_alarm.notification_failures - us-east-1 ] --------------- #

resource "aws_cloudwatch_metric_alarm" "us_east_1_notification_failures" {

  provider = aws.us_east_1

  # Define the Notification-Failure Alarm Properties. EventBridge counts a publish that SNS
  # accepted as delivered, so a subscription that bounces is invisible to the alarm above.
  alarm_actions       = [aws_sns_topic.us_east_1_health.arn]
  alarm_description   = "SNS accepted a security change alert and then failed to deliver it to a recipient."
  alarm_name          = local.notification_failures_alarm_name
  comparison_operator = "GreaterThanOrEqualToThreshold"
  datapoints_to_alarm = 1
  dimensions          = { TopicName = aws_sns_topic.us_east_1.name }
  evaluation_periods  = 1
  metric_name         = "NumberOfNotificationsFailed"
  namespace           = "AWS/SNS"
  ok_actions          = [aws_sns_topic.us_east_1_health.arn]
  period              = 300
  statistic           = "Sum"
  tags                = local.notification_failures_alarm_tags
  threshold           = 1
  treat_missing_data  = "notBreaching"

}

#endregion --- [ aws_cloudwatch_metric_alarm.notification_failures - us-east-1 ] --------------- #

#endregion --- [ aws_cloudwatch_metric_alarm ] ------------------------------------------------- #


#region ------ [ aws_s3_bucket ] --------------------------------------------------------------- #

#region ------ [ aws_s3_bucket - us-east-1 ] --------------------------------------------------- #

resource "aws_s3_bucket" "us_east_1_trail" {

  # Iterate through the Management Event Trail in the provider's region.
  provider = aws.us_east_1
  for_each = local.trails

  # Define the Trail Log Bucket Properties
  bucket = each.value.bucket
  tags   = each.value.bucket_tags

  lifecycle {
    # This bucket is the account's audit record. A destroy here, or a lost state file followed by
    # one, would delete the evidence these alerts exist to raise.
    prevent_destroy = true
  }

}

#endregion --- [ aws_s3_bucket - us-east-1 ] --------------------------------------------------- #

#endregion --- [ aws_s3_bucket ] --------------------------------------------------------------- #


#region ------ [ aws_s3_bucket_public_access_block ] ------------------------------------------- #

#region ------ [ aws_s3_bucket_public_access_block - us-east-1 ] ------------------------------- #

resource "aws_s3_bucket_public_access_block" "us_east_1_trail" {

  # Iterate through the Management Event Trail in the provider's region.
  provider = aws.us_east_1
  for_each = local.trails

  # Define the Trail Log Bucket Public-Access Properties
  block_public_acls       = true
  block_public_policy     = true
  bucket                  = aws_s3_bucket.us_east_1_trail[each.key].id
  ignore_public_acls      = true
  restrict_public_buckets = true

}

#endregion --- [ aws_s3_bucket_public_access_block - us-east-1 ] ------------------------------- #

#endregion --- [ aws_s3_bucket_public_access_block ] ------------------------------------------- #


#region ------ [ aws_s3_bucket_ownership_controls ] -------------------------------------------- #

#region ------ [ aws_s3_bucket_ownership_controls - us-east-1 ] -------------------------------- #

resource "aws_s3_bucket_ownership_controls" "us_east_1_trail" {

  # Iterate through the Management Event Trail in the provider's region.
  provider = aws.us_east_1
  for_each = local.trails

  # Define the Trail Log Bucket Ownership Properties
  bucket = aws_s3_bucket.us_east_1_trail[each.key].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }

}

#endregion --- [ aws_s3_bucket_ownership_controls - us-east-1 ] -------------------------------- #

#endregion --- [ aws_s3_bucket_ownership_controls ] -------------------------------------------- #


#region ------ [ aws_s3_bucket_server_side_encryption_configuration ] -------------------------- #

#region ------ [ aws_s3_bucket_server_side_encryption_configuration - us-east-1 ] -------------- #

#trivy:ignore:AVD-AWS-0132
resource "aws_s3_bucket_server_side_encryption_configuration" "us_east_1_trail" {

  # Iterate through the Management Event Trail in the provider's region.
  provider = aws.us_east_1
  for_each = local.trails

  # Define the Trail Log Bucket Encryption Properties. S3-managed keys rather than the alert key:
  # the logs hold the same metadata the alerts already email, and a customer key here costs a
  # further key and a further grant for no further protection. CIS 3.7 asks for KMS; that
  # deviation is recorded in docs/decision-records/repo/0003.
  bucket = aws_s3_bucket.us_east_1_trail[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }

}

#endregion --- [ aws_s3_bucket_server_side_encryption_configuration - us-east-1 ] -------------- #

#endregion --- [ aws_s3_bucket_server_side_encryption_configuration ] -------------------------- #


#region ------ [ aws_s3_bucket_lifecycle_configuration ] --------------------------------------- #

#region ------ [ aws_s3_bucket_lifecycle_configuration - us-east-1 ] --------------------------- #

resource "aws_s3_bucket_lifecycle_configuration" "us_east_1_trail" {

  # Iterate through the Management Event Trail in the provider's region.
  provider = aws.us_east_1
  for_each = local.trails

  # Define the Trail Log Bucket Lifecycle Properties
  bucket = aws_s3_bucket.us_east_1_trail[each.key].id

  rule {
    id     = "expire-management-event-logs"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    expiration {
      days = 365
    }

    filter {}
  }

}

#endregion --- [ aws_s3_bucket_lifecycle_configuration - us-east-1 ] --------------------------- #

#endregion --- [ aws_s3_bucket_lifecycle_configuration ] --------------------------------------- #


#region ------ [ aws_s3_bucket_policy ] -------------------------------------------------------- #

#region ------ [ aws_s3_bucket_policy - us-east-1 ] -------------------------------------------- #

resource "aws_s3_bucket_policy" "us_east_1_trail" {

  # Iterate through the Management Event Trail in the provider's region.
  provider = aws.us_east_1
  for_each = local.trails

  # Define the Trail Log Bucket Policy Properties
  bucket = aws_s3_bucket.us_east_1_trail[each.key].id
  policy = each.value.bucket_policy

  depends_on = [aws_s3_bucket_public_access_block.us_east_1_trail]

}

#endregion --- [ aws_s3_bucket_policy - us-east-1 ] -------------------------------------------- #

#endregion --- [ aws_s3_bucket_policy ] -------------------------------------------------------- #


#region ------ [ aws_cloudtrail ] -------------------------------------------------------------- #

#region ------ [ aws_cloudtrail - us-east-1 ] -------------------------------------------------- #

# Logs encrypted with S3-managed keys rather than a KMS key is an accepted deviation: see ADR
# repo/0003.
#trivy:ignore:AVD-AWS-0015
resource "aws_cloudtrail" "us_east_1" {

  # Iterate through the Management Event Trail in the provider's region.
  provider = aws.us_east_1
  for_each = local.trails

  # Define the Management Event Trail Properties. Multi-region and global service events are both
  # required rather than preferred: a security group is recorded in the region of the call, and
  # IAM is a global service whose events are recorded in US East (N. Virginia).
  enable_log_file_validation    = true
  include_global_service_events = true
  is_multi_region_trail         = true
  name                          = each.value.name
  s3_bucket_name                = aws_s3_bucket.us_east_1_trail[each.key].id
  tags                          = each.value.tags

  # CloudTrail refuses to create a trail it cannot write to, so the policy has to land first.
  depends_on = [aws_s3_bucket_policy.us_east_1_trail]

  lifecycle {
    # Deleting the trail stops every alert in this framework and ends the account's audit record.
    prevent_destroy = true
  }

}

#endregion --- [ aws_cloudtrail - us-east-1 ] -------------------------------------------------- #

#endregion --- [ aws_cloudtrail ] -------------------------------------------------------------- #


#region ------ [ moved ] ----------------------------------------------------------------------- #

# The trail family was once addressed by count. These carry that state to the keyed addresses
# rather than planning a replacement the trail and bucket refuse; a deployment that never had the
# old addresses is unaffected.
moved {
  from = aws_s3_bucket.us_east_1_trail[0]
  to   = aws_s3_bucket.us_east_1_trail["management-events"]
}

moved {
  from = aws_s3_bucket_public_access_block.us_east_1_trail[0]
  to   = aws_s3_bucket_public_access_block.us_east_1_trail["management-events"]
}

moved {
  from = aws_s3_bucket_ownership_controls.us_east_1_trail[0]
  to   = aws_s3_bucket_ownership_controls.us_east_1_trail["management-events"]
}

moved {
  from = aws_s3_bucket_server_side_encryption_configuration.us_east_1_trail[0]
  to   = aws_s3_bucket_server_side_encryption_configuration.us_east_1_trail["management-events"]
}

moved {
  from = aws_s3_bucket_lifecycle_configuration.us_east_1_trail[0]
  to   = aws_s3_bucket_lifecycle_configuration.us_east_1_trail["management-events"]
}

moved {
  from = aws_s3_bucket_policy.us_east_1_trail[0]
  to   = aws_s3_bucket_policy.us_east_1_trail["management-events"]
}

moved {
  from = aws_cloudtrail.us_east_1[0]
  to   = aws_cloudtrail.us_east_1["management-events"]
}

#endregion --- [ moved ] ----------------------------------------------------------------------- #
