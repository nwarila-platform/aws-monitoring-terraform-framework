# Output values: the non-secret record of what was deployed. Deployment identity is not
# re-exported - it is written into every tag map, so the resource tags themselves are the record.


#region ------ [ Resource(s): aws_kms_key ] ---------------------------------------------------- #

output "alert_key" {
  description = <<-EOT
    The key encrypting both topics, and whether this framework owns it. A supplied key's rotation
    and policy belong to whoever owns it; this deployment only uses it.
  EOT
  value = {
    arn               = local.alert_key_arn
    framework_managed = var.alert_key_alias == null
  }
}

#endregion --- [ Resource(s): aws_kms_key ] ---------------------------------------------------- #


#region ------ [ Resource(s): aws_sns_topic ] -------------------------------------------------- #

output "alert_topic_arn" {
  description = "ARN of the SNS topic every change alert is published to."
  value       = aws_sns_topic.us_east_1.arn
}

#endregion --- [ Resource(s): aws_sns_topic ] -------------------------------------------------- #


#region ------ [ Resource(s): aws_sns_topic_subscription ] ------------------------------------- #

output "alert_subscriptions" {
  description = <<-EOT
    Email subscriptions keyed by address. pending_confirmation stays true until the recipient
    follows the link SNS emailed them; an address that is still pending receives nothing.
  EOT
  value = {
    for email, subscription in aws_sns_topic_subscription.us_east_1 : email => {
      arn                  = subscription.arn
      pending_confirmation = subscription.pending_confirmation
    }
  }
}

#endregion --- [ Resource(s): aws_sns_topic_subscription ] ------------------------------------- #


#region ------ [ Resource(s): aws_cloudwatch_event_rule ] -------------------------------------- #

output "alert_rules" {
  description = "EventBridge rules keyed by change alert, with the exact API calls each one matches."
  value = {
    for key, rule in aws_cloudwatch_event_rule.us_east_1 : key => {
      arn         = rule.arn
      name        = rule.name
      event_names = local.change_alerts[key].event_names
    }
  }
}

#endregion --- [ Resource(s): aws_cloudwatch_event_rule ] -------------------------------------- #


#region ------ [ Resource(s): aws_sns_topic.health ] ------------------------------------------- #

output "health_topic_arn" {
  description = <<-EOT
    ARN of the topic that reports on the alert channel itself. Separate from the alert topic on
    purpose: an alarm about a broken alert topic cannot be delivered by that topic.
  EOT
  value       = aws_sns_topic.us_east_1_health.arn
}

#endregion --- [ Resource(s): aws_sns_topic.health ] ------------------------------------------- #


#region ------ [ Resource(s): aws_sqs_queue ] -------------------------------------------------- #

output "undelivered_queue_url" {
  description = "URL of the queue holding alerts EventBridge could not deliver, kept for fourteen days."
  value       = aws_sqs_queue.us_east_1_dlq.id
}

#endregion --- [ Resource(s): aws_sqs_queue ] -------------------------------------------------- #


#region ------ [ Resource(s): aws_cloudwatch_metric_alarm ] ------------------------------------ #

output "health_alarms" {
  description = "Names of the alarms watching the alert channel, for confirming they exist after a deploy."
  value = sort(concat(
    [for alarm in aws_cloudwatch_metric_alarm.us_east_1_failed_invocations : alarm.alarm_name],
    [
      aws_cloudwatch_metric_alarm.us_east_1_undelivered.alarm_name,
      aws_cloudwatch_metric_alarm.us_east_1_notification_failures.alarm_name,
    ],
  ))
}

#endregion --- [ Resource(s): aws_cloudwatch_metric_alarm ] ------------------------------------ #
