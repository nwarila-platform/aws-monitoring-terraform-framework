# Managed resources. Consumes the shaped maps from locals.tf.


#region ------ [ aws_kms_key ] ----------------------------------------------------------------- #

#region ------ [ aws_kms_key - us-east-1 ] ----------------------------------------------------- #

resource "aws_kms_key" "us_east_1" {

  # Define the Alert Topic Key Properties
  provider = aws.us_east_1

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

  # Define the Alert Topic Key Alias Properties
  provider = aws.us_east_1

  name          = "alias/${local.alert_name}"
  target_key_id = aws_kms_key.us_east_1.key_id

}

#endregion --- [ aws_kms_alias - us-east-1 ] --------------------------------------------------- #

#endregion --- [ aws_kms_alias ] --------------------------------------------------------------- #


#region ------ [ aws_sns_topic ] --------------------------------------------------------------- #

#region ------ [ aws_sns_topic - us-east-1 ] --------------------------------------------------- #

resource "aws_sns_topic" "us_east_1" {

  # Define the Alert Topic Properties
  provider = aws.us_east_1

  # The display name is the sender name recipients see. EventBridge sets no per-message subject,
  # so every email arrives under SNS's fixed subject and the headline is the body's first line.
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

  # Define the Alert Topic Policy Properties
  provider = aws.us_east_1

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
  for_each = toset(var.alert_emails)

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

  # Define the Health Topic Properties
  provider = aws.us_east_1

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

  # Define the Health Topic Policy Properties
  provider = aws.us_east_1

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
  for_each = toset(var.alert_emails)

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

  # Define the Dead-Letter Queue Properties
  provider = aws.us_east_1

  # Fourteen days is the SQS maximum and the point of the queue: an alert that could not be
  # delivered is kept until somebody reads it, rather than dropped when retries run out.
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

  # Define the Dead-Letter Queue Policy Properties
  provider = aws.us_east_1

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
  name           = "${local.alert_name}-${each.key}"
  state          = "ENABLED"
  tags           = merge(local.identity_tags, { Name = "${local.alert_name}-${each.key}" })

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

  input_transformer {
    input_paths    = local.message_paths
    input_template = local.message_templates[each.key]
  }

  dead_letter_config {
    arn = aws_sqs_queue.us_east_1_dlq.arn
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
  alarm_name          = "${local.alert_name}-${each.key}-failed-invocations"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  datapoints_to_alarm = 1
  dimensions          = { RuleName = aws_cloudwatch_event_rule.us_east_1[each.key].name }
  evaluation_periods  = 1
  metric_name         = "FailedInvocations"
  namespace           = "AWS/Events"
  ok_actions          = [aws_sns_topic.us_east_1_health.arn]
  period              = 300
  statistic           = "Sum"
  tags                = merge(local.identity_tags, { Name = "${local.alert_name}-${each.key}-failed-invocations" })
  threshold           = 1
  treat_missing_data  = "notBreaching"

}

#endregion --- [ aws_cloudwatch_metric_alarm.failed_invocations - us-east-1 ] ------------------ #

#region ------ [ aws_cloudwatch_metric_alarm.undelivered - us-east-1 ] ------------------------- #

resource "aws_cloudwatch_metric_alarm" "us_east_1_undelivered" {

  # Define the Undelivered-Alert Alarm Properties. A message in the queue is an alert that was
  # never emailed; the queue holds it for fourteen days so it can still be read.
  provider = aws.us_east_1

  alarm_actions       = [aws_sns_topic.us_east_1_health.arn]
  alarm_description   = "A security change alert was never delivered and is waiting in ${local.dlq_name}."
  alarm_name          = "${local.alert_name}-undelivered"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  datapoints_to_alarm = 1
  dimensions          = { QueueName = aws_sqs_queue.us_east_1_dlq.name }
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  ok_actions          = [aws_sns_topic.us_east_1_health.arn]
  period              = 300
  statistic           = "Maximum"
  tags                = merge(local.identity_tags, { Name = "${local.alert_name}-undelivered" })
  threshold           = 1
  treat_missing_data  = "notBreaching"

}

#endregion --- [ aws_cloudwatch_metric_alarm.undelivered - us-east-1 ] ------------------------- #

#region ------ [ aws_cloudwatch_metric_alarm.notification_failures - us-east-1 ] --------------- #

resource "aws_cloudwatch_metric_alarm" "us_east_1_notification_failures" {

  # Define the Notification-Failure Alarm Properties. EventBridge counts a publish that SNS
  # accepted as delivered, so a subscription that bounces is invisible to the alarm above.
  provider = aws.us_east_1

  alarm_actions       = [aws_sns_topic.us_east_1_health.arn]
  alarm_description   = "SNS accepted a security change alert and then failed to deliver it to a recipient."
  alarm_name          = "${local.alert_name}-notification-failures"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  datapoints_to_alarm = 1
  dimensions          = { TopicName = aws_sns_topic.us_east_1.name }
  evaluation_periods  = 1
  metric_name         = "NumberOfNotificationsFailed"
  namespace           = "AWS/SNS"
  ok_actions          = [aws_sns_topic.us_east_1_health.arn]
  period              = 300
  statistic           = "Sum"
  tags                = merge(local.identity_tags, { Name = "${local.alert_name}-notification-failures" })
  threshold           = 1
  treat_missing_data  = "notBreaching"

}

#endregion --- [ aws_cloudwatch_metric_alarm.notification_failures - us-east-1 ] --------------- #

#endregion --- [ aws_cloudwatch_metric_alarm ] ------------------------------------------------- #
