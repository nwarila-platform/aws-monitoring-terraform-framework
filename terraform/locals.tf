# The brain of the plan: every object consumed by resources.tf is shaped here from
# variables and data lookups.

# Statically Configured LOCALS
locals {

  #region ------ [ Deployment Identity Tags ] -------------------------------------------------- #

  # The identity keys whose value is identical on every resource, applied as provider
  # default_tags in providers.tf and merged under each resource's Name below.
  identity_tags = {
    CommitSha    = var.commit_sha
    Environment  = var.environment
    ManagedBy    = "Terraform"
    Repository   = var.repository
    RepositoryId = var.repository_id
    RunId        = var.run_id
  }

  #endregion --- [ Deployment Identity Tags ] -------------------------------------------------- #


  #region ------ [ Alert Channel ] ------------------------------------------------------------- #

  # One topic, one key, and one name for both. Named for what it carries so the email sender,
  # the console entry, and the KMS alias all read the same.
  alert_name = "security-change-alerts"

  alert_tags = merge(local.identity_tags, { Name = local.alert_name })

  # EventBridge publishes through the topic's key, so the key policy must admit it. The SNS
  # developer guide's statement for event sources is reproduced exactly: kms:GenerateDataKey* and
  # kms:Decrypt to events.amazonaws.com, with NO aws:SourceArn or aws:SourceAccount condition,
  # because that guide states those conditions are unsupported for EventBridge publishing to an
  # encrypted topic. The root statement keeps the key administrable by the account after the
  # runner's session ends; without it the key would be owned by nobody.
  alert_key_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountAdministersTheKey"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "EventBridgePublishesThroughTheKey"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = ["kms:GenerateDataKey*", "kms:Decrypt"]
        Resource  = "*"
      },
    ]
  })

  # The topic accepts publishes from EventBridge and nothing else. The EventBridge user guide's
  # SNS statement is reproduced as written, which carries no source condition; the rules that
  # publish here are the only ones in this account matching these events, so the residual is an
  # EventBridge rule in this account choosing this topic as a target.
  alert_topic_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EventBridgePublishesChangeAlerts"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.us_east_1.arn
      },
    ]
  })

  #endregion --- [ Alert Channel ] ------------------------------------------------------------- #


  #region ------ [ Change Alerts ] ------------------------------------------------------------- #

  # What gets an email. One entry is one EventBridge rule: the CloudTrail event source it
  # watches and the exact write calls that count as a change. Read calls never appear, and a
  # rule in the default ENABLED state matches write management events only, so widening a list
  # here is the whole act of widening the alert.
  #
  # Every event named here is delivered in us-east-1: security group calls because that is the
  # region the fleet deploys into, and IAM calls because CloudTrail records global-service events
  # as occurring in US East (N. Virginia).
  change_alerts = {
    security-group = {
      description  = "A security group, or one of its rules, was created, changed, or deleted."
      headline     = "Security group changed"
      source       = "aws.ec2"
      event_source = "ec2.amazonaws.com"
      event_names = [
        "AuthorizeSecurityGroupEgress",
        "AuthorizeSecurityGroupIngress",
        "CreateSecurityGroup",
        "DeleteSecurityGroup",
        "ModifySecurityGroupRules",
        "RevokeSecurityGroupEgress",
        "RevokeSecurityGroupIngress",
        "UpdateSecurityGroupRuleDescriptionsEgress",
        "UpdateSecurityGroupRuleDescriptionsIngress",
      ]
    }
    iam-role = {
      description  = "An IAM role, its trust, its permissions, its boundary, or its tags changed."
      headline     = "IAM role changed"
      source       = "aws.iam"
      event_source = "iam.amazonaws.com"
      event_names = [
        "AttachRolePolicy",
        "CreateRole",
        "CreateServiceLinkedRole",
        "DeleteRole",
        "DeleteRolePermissionsBoundary",
        "DeleteRolePolicy",
        "DeleteServiceLinkedRole",
        "DetachRolePolicy",
        "PutRolePermissionsBoundary",
        "PutRolePolicy",
        "TagRole",
        "UntagRole",
        "UpdateAssumeRolePolicy",
        "UpdateRole",
        "UpdateRoleDescription",
      ]
    }
  }

  # CloudTrail delivers API calls to EventBridge under one fixed detail-type; the source and
  # eventSource narrow to the service, and eventName to the exact calls above.
  event_patterns = {
    for key, alert in local.change_alerts : key => jsonencode({
      source        = [alert.source]
      "detail-type" = ["AWS API Call via CloudTrail"]
      detail = {
        eventSource = [alert.event_source]
        eventName   = alert.event_names
      }
    })
  }

  # The fields the email quotes, read from the CloudTrail record. requestParameters is a JSON
  # object and is inlined as one, so the email shows exactly what was asked of the API without
  # this framework knowing every call's shape.
  message_paths = {
    account           = "$.account"
    eventId           = "$.detail.eventID"
    eventName         = "$.detail.eventName"
    principal         = "$.detail.userIdentity.arn"
    region            = "$.region"
    requestParameters = "$.detail.requestParameters"
    sourceIp          = "$.detail.sourceIPAddress"
    time              = "$.detail.eventTime"
  }

  # Plain text, not JSON: SNS emails the message body verbatim. Angle-bracket names are the
  # message_paths keys above and are substituted by EventBridge, not by Terraform.
  message_templates = {
    for key, alert in local.change_alerts : key => <<-EOT
      ${alert.headline} in AWS account <account>, region <region>.

      Action      <eventName>
      Principal   <principal>
      Source IP   <sourceIp>
      Time (UTC)  <time>
      Event ID    <eventId>

      Request parameters:
      <requestParameters>

      Recorded by CloudTrail and delivered by the EventBridge rule ${local.alert_name}-${key}.
      Look the event up in CloudTrail Event history by its Event ID for the full record.
    EOT
  }

  #endregion --- [ Change Alerts ] ------------------------------------------------------------- #

}
