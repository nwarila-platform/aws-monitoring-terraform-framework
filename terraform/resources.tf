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

}

#endregion --- [ aws_cloudwatch_event_target - us-east-1 ] ------------------------------------- #

#endregion --- [ aws_cloudwatch_event_target ] ------------------------------------------------- #
