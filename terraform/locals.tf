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


  #region ------ [ Global-Service Region ] ----------------------------------------------------- #

  # CloudTrail records IAM calls in one region per partition and delivers them to EventBridge only
  # there, so an IAM rule anywhere else is created successfully and never fires. A fact about AWS,
  # not a choice: providers.tf still decides where a deployment goes, and this refuses the choices
  # that would silence the IAM alert. A partition not listed here is not checked.
  global_service_regions = { aws = "us-east-1", aws-us-gov = "us-gov-west-1" }

  #endregion --- [ Global-Service Region ] ----------------------------------------------------- #


  #region ------ [ Alert Channel ] ------------------------------------------------------------- #

  # One topic, one key, and one name for both. Named for what it carries so the email sender,
  # the console entry, and the KMS alias all read the same.
  alert_name = "security-change-alerts"

  alert_tags = merge(local.identity_tags, { Name = local.alert_name })

  # The channel that reports on the alert channel. It is deliberately a second topic: an alarm
  # about a broken alert topic cannot be delivered by that same topic.
  health_name = "${local.alert_name}-health"
  health_tags = merge(local.identity_tags, { Name = local.health_name })

  # Where undelivered events land. EventBridge drops an event for good once its retries are
  # exhausted, so without this a publishing failure loses the security change entirely.
  dlq_name = "${local.alert_name}-dlq"
  dlq_tags = merge(local.identity_tags, { Name = local.dlq_name })

  # The role deploying this framework, path and partition included.
  deploy_principal_arn = data.aws_iam_session_context.current.issuer_arn

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
        Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        # CreateKey refuses a policy that would not let its caller update the policy afterwards.
        # Granting that through IAM would hang on a tag the key does not have until it exists, so
        # the deploying role administers the key through the key policy itself.
        Sid       = "DeployRoleAdministersTheKey"
        Effect    = "Allow"
        Principal = { AWS = local.deploy_principal_arn }
        Action = [
          "kms:CancelKeyDeletion",
          "kms:CreateAlias",
          "kms:DeleteAlias",
          "kms:DescribeKey",
          "kms:DisableKeyRotation",
          "kms:EnableKeyRotation",
          "kms:GetKeyPolicy",
          "kms:GetKeyRotationStatus",
          "kms:ListResourceTags",
          "kms:PutKeyPolicy",
          "kms:ScheduleKeyDeletion",
          "kms:TagResource",
          "kms:UntagResource",
          "kms:UpdateAlias",
          "kms:UpdateKeyDescription",
        ]
        Resource = "*"
      },
      {
        Sid       = "EventBridgePublishesThroughTheKey"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = ["kms:GenerateDataKey*", "kms:Decrypt"]
        Resource  = "*"
      },
      {
        # The health topic carries alarm notifications and shares this key; CloudWatch is listed
        # as an event source in the same SNS guide, with the same two actions.
        Sid       = "CloudWatchPublishesThroughTheKey"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
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

  health_topic_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "CloudWatchPublishesAlarms"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.us_east_1_health.arn
        Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
      },
    ]
  })

  # Only the two rules this framework owns may write to the queue, named individually rather
  # than by wildcard so a third rule cannot quietly fill it.
  dlq_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EventBridgeSendsUndeliveredAlerts"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.us_east_1_dlq.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = [for rule in aws_cloudwatch_event_rule.us_east_1 : rule.arn]
          }
        }
      },
    ]
  })

  #endregion --- [ Alert Channel ] ------------------------------------------------------------- #


  #region ------ [ Management Event Trail ] ---------------------------------------------------- #

  # The trail whose records these alerts read. Named for what it carries rather than for the
  # alerts, because a trail is account-wide audit infrastructure that outlives them.
  trail_name   = "management-events"
  trail_bucket = "${data.aws_caller_identity.current.account_id}-cloudtrail"
  trail_tags   = merge(local.identity_tags, { Name = local.trail_name })

  # Composed rather than read from the resource: the bucket policy has to name the trail, and the
  # trail cannot be created until that policy exists.
  trail_arn = format(
    "arn:%s:cloudtrail:%s:%s:trail/%s",
    data.aws_partition.current.partition,
    data.aws_region.current.region,
    data.aws_caller_identity.current.account_id,
    local.trail_name,
  )
  trail_bucket_arn = "arn:${data.aws_partition.current.partition}:s3:::${local.trail_bucket}"

  # The policy CloudTrail requires to write, with the source condition AWS documents for it. The
  # object path is fixed by CloudTrail and includes the account id.
  trail_bucket_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "CloudTrailChecksBucketAcl"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = local.trail_bucket_arn
        Condition = { StringEquals = { "aws:SourceArn" = local.trail_arn } }
      },
      {
        Sid       = "CloudTrailWritesLogs"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${local.trail_bucket_arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "aws:SourceArn" = local.trail_arn
          }
        }
      },
    ]
  })

  #endregion --- [ Management Event Trail ] ---------------------------------------------------- #


  #region ------ [ Change Alerts ] ------------------------------------------------------------- #

  # What gets an email. One entry is one EventBridge rule: the CloudTrail event source it
  # watches and the exact write calls that count as a change. Read calls never appear, and a
  # rule in the default ENABLED state matches write management events only, so widening a list
  # here is the whole act of widening the alert.
  #
  # Every event named here must arrive in the provider's region. Security group calls are recorded
  # where they are made, so the deployment's workloads must live in that region (see
  # docs/reference/invariants.md). IAM calls are recorded only in the partition's global-service
  # region, so the provider must target that region too; the rules refuse any other.
  change_alerts = {
    security-group = {
      description  = "A security group, its rules, or its VPC associations were created, changed, or deleted."
      headline     = "Security group changed"
      source       = "aws.ec2"
      event_source = "ec2.amazonaws.com"
      # Pipeline roles are exempt here and nowhere else: automation that rewrites security groups
      # on every run would bury the changes a person has to see.
      exempt_pipelines = true
      event_names = [
        "AssociateSecurityGroupVpc",
        "AuthorizeSecurityGroupEgress",
        "AuthorizeSecurityGroupIngress",
        "CreateSecurityGroup",
        "DeleteSecurityGroup",
        "DisassociateSecurityGroupVpc",
        "ModifySecurityGroupRules",
        "RevokeSecurityGroupEgress",
        "RevokeSecurityGroupIngress",
        "UpdateSecurityGroupRuleDescriptionsEgress",
        "UpdateSecurityGroupRuleDescriptionsIngress",
      ]
    }
    iam = {
      description  = "An IAM role, or a managed policy that grants roles their permissions, changed."
      headline     = "IAM permissions changed"
      source       = "aws.iam"
      event_source = "iam.amazonaws.com"
      # Never exempt: an IAM change is the quietest way to widen access, whoever makes it.
      exempt_pipelines = false
      # The policy calls are here because a role's permissions change without any role-level
      # event: SetDefaultPolicyVersion on an attached managed policy re-grants every role that
      # holds it. AcquireRole builds a role from a role template and emits no CreateRole.
      event_names = [
        "AcquireRole",
        "AddRoleToInstanceProfile",
        "AttachRolePolicy",
        "CreatePolicy",
        "CreatePolicyVersion",
        "CreateRole",
        "CreateServiceLinkedRole",
        "DeletePolicy",
        "DeletePolicyVersion",
        "DeleteRole",
        "DeleteRolePermissionsBoundary",
        "DeleteRolePolicy",
        "DeleteServiceLinkedRole",
        "DetachRolePolicy",
        "PutRolePermissionsBoundary",
        "PutRolePolicy",
        "RemoveRoleFromInstanceProfile",
        "SetDefaultPolicyVersion",
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
  #
  # The exemption is two branches under $or rather than one anything-but, because a bare
  # anything-but on a nested field never matches an event that lacks the field: a root-user or
  # AWS-service call carries no sessionIssuer, and excluding a pipeline role would have silently
  # excluded those too. The second branch matches exactly that shape. tools/check_event_patterns.sh
  # proves both branches against AWS's own matcher before any apply.
  pipeline_exemption = {
    "$or" = [
      {
        userIdentity = {
          sessionContext = { sessionIssuer = { userName = [{ "anything-but" = var.exempt_pipeline_roles }] } }
        }
      },
      {
        userIdentity = {
          sessionContext = { sessionIssuer = { userName = [{ exists = false }] } }
        }
      },
    ]
  }

  event_patterns = {
    for key, alert in local.change_alerts : key => jsonencode({
      source        = [alert.source]
      "detail-type" = ["AWS API Call via CloudTrail"]
      detail = merge(
        {
          eventSource = [alert.event_source]
          eventName   = alert.event_names
        },
        alert.exempt_pipelines && length(var.exempt_pipeline_roles) > 0 ? local.pipeline_exemption : {},
      )
    })
  }

  # The fields quoted in the message. Only paths that every "AWS API Call via CloudTrail" event
  # carries: a path that is absent at runtime is dropped from the rendered template, which would
  # leave malformed JSON. The principal, the source address and the request parameters are absent
  # on some events and are read from the whole-event value instead.
  message_paths = {
    account   = "$.account"
    eventName = "$.detail.eventName"
    region    = "$.region"
    time      = "$.time"
  }

  # EventBridge parses this template as JSON, so it IS JSON: a bare multi-line string is rejected
  # by PutTargets and the target is never installed. Unquoted <placeholders> are substituted with
  # the JSON value, so a string arrives quoted. aws.events.event.json is the reserved whole-event
  # variable and is legal only as a value, which is what keeps requestParameters an object rather
  # than the quote-stripped text an object becomes inside a string.
  message_templates = {
    for key, alert in local.change_alerts : key => <<-EOT
      {
        "alert": "${alert.headline}",
        "account": <account>,
        "region": <region>,
        "action": <eventName>,
        "time": <time>,
        "rule": "${local.alert_name}-${key}",
        "event": <aws.events.event.json>
      }
    EOT
  }

  #endregion --- [ Change Alerts ] ------------------------------------------------------------- #

}
