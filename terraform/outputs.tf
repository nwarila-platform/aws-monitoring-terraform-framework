# Output values: the non-secret record of what was deployed. Deployment identity is not
# re-exported - it is written into every tag map, so the resource tags themselves are the record.


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
