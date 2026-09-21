mock_provider "aws" {
  alias = "us_east_1"

  # The key policy names the account root, so the identity lookup has to return an account-shaped
  # value rather than a random string.
  # The commercial partition and the lab's region, so every ARN the framework writes renders the
  # way the lab deploys it. tests/portability.tftest.hcl renders the GovCloud case.
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

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = join("", ["123456", "789012"])
      arn        = "arn:aws:sts::${join("", ["123456", "789012"])}:assumed-role/example-deploy-role/aws-deploy-42"
    }
  }

  # The subscription, the topic policy and the target all validate the topic ARN's shape before
  # a mocked apply, so the mock has to return an ARN rather than a random string.
  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:us-east-1:${join("", ["123456", "789012"])}:security-change-alerts"
    }
  }

  # The target's dead-letter ARN is validated the same way.
  mock_resource "aws_sqs_queue" {
    defaults = {
      arn = "arn:aws:sqs:us-east-1:${join("", ["123456", "789012"])}:security-change-alerts-dlq"
      id  = "https://sqs.us-east-1.amazonaws.com/${join("", ["123456", "789012"])}/security-change-alerts-dlq"
    }
  }
}

variables {
  repository            = "nwarila-platform/aws-monitoring-terraform-framework"
  repository_id         = "123456789"
  commit_sha            = "0123456789abcdef0123456789abcdef01234567"
  run_id                = "42"
  environment           = "test"
  manage_trail          = false
  alert_emails          = ["security@example.com", "oncall@example.com"]
  exempt_pipeline_roles = ["nwarila-platform_pdq-deploy-inventory_runner"]
}

# The rule IS the alert. Every write call that counts is named here, as an exact list, so a
# widening or narrowing of what gets an email is visible as a test diff and nowhere else.
run "security_group_rule_matches_exactly_the_documented_write_calls" {
  command = plan

  assert {
    condition = jsondecode(aws_cloudwatch_event_rule.us_east_1["security-group"].event_pattern).detail.eventName == [
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
    error_message = "The security-group rule must match exactly the eleven EC2 security group write calls, and nothing else."
  }

  assert {
    condition = alltrue([
      jsondecode(aws_cloudwatch_event_rule.us_east_1["security-group"].event_pattern).source == ["aws.ec2"],
      jsondecode(aws_cloudwatch_event_rule.us_east_1["security-group"].event_pattern)["detail-type"] == ["AWS API Call via CloudTrail"],
      jsondecode(aws_cloudwatch_event_rule.us_east_1["security-group"].event_pattern).detail.eventSource == ["ec2.amazonaws.com"],
    ])
    error_message = "The security-group rule must match the CloudTrail API-call events of the EC2 service."
  }
}

# A role's permissions change with no role-level event when an attached managed policy gets a new
# default version, so the policy calls belong to this alert. AcquireRole builds a role from a
# template and emits no CreateRole.
run "iam_rule_matches_exactly_the_documented_write_calls" {
  command = plan

  assert {
    condition = jsondecode(aws_cloudwatch_event_rule.us_east_1["iam"].event_pattern).detail.eventName == [
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
    error_message = "The iam rule must match exactly the twenty-three IAM role and policy write calls, and nothing else."
  }

  assert {
    condition = alltrue([
      jsondecode(aws_cloudwatch_event_rule.us_east_1["iam"].event_pattern).source == ["aws.iam"],
      jsondecode(aws_cloudwatch_event_rule.us_east_1["iam"].event_pattern).detail.eventSource == ["iam.amazonaws.com"],
    ])
    error_message = "The iam rule must match the CloudTrail API-call events of the IAM service."
  }
}

# The exemption is the one place an alert is deliberately narrowed, so its shape is pinned. Two
# branches: the change was made by a role that is not exempt, or by an identity that carries no
# assumed-role name at all. Without the second branch, a root-user or service-made change would
# be silently dropped along with the pipelines.
run "the_pipeline_exemption_still_matches_an_identity_with_no_session" {
  command = plan

  assert {
    condition = jsondecode(aws_cloudwatch_event_rule.us_east_1["security-group"].event_pattern).detail["$or"] == [
      {
        userIdentity = {
          sessionContext = {
            sessionIssuer = {
              userName = [{ "anything-but" = ["nwarila-platform_pdq-deploy-inventory_runner"] }]
            }
          }
        }
      },
      {
        userIdentity = {
          sessionContext = {
            sessionIssuer = {
              userName = [{ exists = false }]
            }
          }
        }
      },
    ]
    error_message = "The security-group exemption must exclude the named roles while still matching events that carry no assumed-role identity."
  }

  assert {
    condition     = !can(jsondecode(aws_cloudwatch_event_rule.us_east_1["iam"].event_pattern).detail["$or"])
    error_message = "The IAM alert must never exempt a principal."
  }
}

run "no_exempt_roles_means_no_exemption_clause" {
  command = plan

  variables {
    exempt_pipeline_roles = []
  }

  assert {
    condition = alltrue([
      for key in ["security-group", "iam"] :
      !can(jsondecode(aws_cloudwatch_event_rule.us_east_1[key].event_pattern).detail["$or"])
    ])
    error_message = "An empty exemption list must leave the patterns matching every principal."
  }
}

# CloudTrail delivers to the default bus only, and ENABLED is the state that matches write
# management events. Either drifting would silence the alert with a green plan.
run "rules_live_on_the_default_bus_and_are_enabled" {
  command = plan

  assert {
    condition = alltrue([
      for key, rule in aws_cloudwatch_event_rule.us_east_1 : alltrue([
        rule.event_bus_name == "default",
        rule.state == "ENABLED",
        rule.name == "security-change-alerts-${key}",
      ])
    ])
    error_message = "Every rule must be ENABLED on the default event bus and named security-change-alerts-<key>."
  }

  assert {
    condition     = sort(keys(aws_cloudwatch_event_rule.us_east_1)) == sort(["iam", "security-group"])
    error_message = "Exactly two change alerts exist: iam and security-group."
  }
}

# EventBridge parses the template as JSON and rejects anything else at PutTargets, which no
# mocked provider ever calls. Substituting each placeholder with a JSON literal and decoding the
# result is the closest a test can get to that check.
run "the_message_template_is_json" {
  command = plan

  assert {
    condition = alltrue([
      for key, target in aws_cloudwatch_event_target.us_east_1 :
      can(jsondecode(replace(target.input_transformer[0].input_template, "/<[^>]*>/", "0")))
    ])
    error_message = "Each input template must be valid JSON once its placeholders are substituted; a bare string is rejected by PutTargets."
  }

  assert {
    condition = alltrue([
      for key, target in aws_cloudwatch_event_target.us_east_1 : alltrue([
        # The whole event as a JSON value: the only way requestParameters survives as an object.
        strcontains(target.input_transformer[0].input_template, "\"event\": <aws.events.event.json>"),
        strcontains(target.input_transformer[0].input_template, local.change_alerts[key].headline),
        strcontains(target.input_transformer[0].input_template, "security-change-alerts-${key}"),
      ])
    ])
    error_message = "Each template must carry the whole event, the alert's headline, and the rule that produced it."
  }

  assert {
    condition = alltrue([
      for key, target in aws_cloudwatch_event_target.us_east_1 : alltrue([
        sort(keys(target.input_transformer[0].input_paths)) == sort(["account", "eventName", "region", "time"]),
        alltrue([
          for name in keys(target.input_transformer[0].input_paths) :
          strcontains(target.input_transformer[0].input_template, "<${name}>")
        ]),
      ])
    ])
    error_message = "Every input path must be a field every CloudTrail API-call event carries, and must be quoted in the template."
  }
}

# Computed ARNs are unknown at plan, so the wiring between rule, target, topic and key is
# asserted after a mocked apply.
run "every_rule_publishes_to_the_one_encrypted_topic" {
  command = apply

  assert {
    condition = alltrue([
      for key, target in aws_cloudwatch_event_target.us_east_1 : alltrue([
        target.arn == aws_sns_topic.us_east_1.arn,
        target.rule == aws_cloudwatch_event_rule.us_east_1[key].name,
        target.event_bus_name == "default",
      ])
    ])
    error_message = "Each rule's target must be the framework topic on the default bus."
  }

  assert {
    condition     = aws_sns_topic.us_east_1.kms_master_key_id == aws_kms_key.us_east_1.key_id
    error_message = "The topic must be encrypted with the framework's own key."
  }

  assert {
    condition     = aws_kms_alias.us_east_1.target_key_id == aws_kms_key.us_east_1.key_id
    error_message = "The alias must point at the framework's own key."
  }
}

# The SNS developer guide's statement for event sources, reproduced exactly: the two KMS actions
# to events.amazonaws.com with no condition, because the guide says a source condition is
# unsupported on that path. Losing it would fail every publish silently.
run "the_key_admits_eventbridge_and_stays_administrable" {
  command = plan

  assert {
    condition = contains(jsondecode(aws_kms_key.us_east_1.policy).Statement, {
      Sid       = "EventBridgePublishesThroughTheKey"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = ["kms:GenerateDataKey*", "kms:Decrypt"]
      Resource  = "*"
    })
    error_message = "The key policy must grant events.amazonaws.com kms:GenerateDataKey* and kms:Decrypt with no condition."
  }

  assert {
    condition = contains(jsondecode(aws_kms_key.us_east_1.policy).Statement, {
      Sid       = "AccountAdministersTheKey"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "kms:*"
      Resource  = "*"
    })
    error_message = "The key policy must keep the account root as administrator."
  }

  assert {
    condition = alltrue([
      aws_kms_key.us_east_1.enable_key_rotation == true,
      aws_kms_key.us_east_1.deletion_window_in_days == 30,
      aws_kms_alias.us_east_1.name == "alias/security-change-alerts",
    ])
    error_message = "The key rotates yearly, waits the full 30 days before deletion, and is aliased as security-change-alerts."
  }
}

# KMS refuses to create a key whose policy would not let the caller update it afterwards. The
# deploying role is named in the key policy so that check never depends on a tag the key does not
# have yet; its ARN is recovered from the assumed-role session the deploy runs as.
run "the_key_policy_names_the_role_that_deploys_it" {
  command = plan

  assert {
    condition = alltrue([
      for statement in jsondecode(aws_kms_key.us_east_1.policy).Statement : alltrue([
        statement.Principal.AWS == "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/example-deploy-role",
        contains(statement.Action, "kms:PutKeyPolicy"),
      ])
      if statement.Sid == "DeployRoleAdministersTheKey"
    ])
    error_message = "The key policy must let the deploying role, not its session, administer the key."
  }

  assert {
    condition     = length([for statement in jsondecode(aws_kms_key.us_east_1.policy).Statement : statement if statement.Sid == "DeployRoleAdministersTheKey"]) == 1
    error_message = "Exactly one statement names the deploying role."
  }
}

run "a_caller_that_is_not_an_assumed_role_is_named_as_itself" {
  command = plan

  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:user/operator"
    }
  }

  assert {
    condition     = local.deploy_principal_arn == "arn:aws:iam::123456789012:user/operator"
    error_message = "An IAM user or role ARN must pass through unchanged."
  }
}

run "the_topic_accepts_publishes_from_eventbridge_only" {
  command = apply

  assert {
    condition = jsondecode(aws_sns_topic_policy.us_east_1.policy).Statement == [
      {
        Sid       = "EventBridgePublishesChangeAlerts"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.us_east_1.arn
      },
    ]
    error_message = "The topic policy must carry exactly one statement: events.amazonaws.com may sns:Publish to this topic."
  }
}

run "one_email_subscription_per_recipient" {
  command = plan

  assert {
    condition = alltrue([
      sort(keys(aws_sns_topic_subscription.us_east_1)) == sort(["oncall@example.com", "security@example.com"]),
      alltrue([
        for email, subscription in aws_sns_topic_subscription.us_east_1 :
        subscription.protocol == "email" && subscription.endpoint == email
      ]),
    ])
    error_message = "Each address in alert_emails must be exactly one email subscription."
  }
}

# The bootstrap state outside prod: rules and topic exist, nobody is subscribed, nothing is
# delivered. prod rejects this, which is covered in validation.tftest.hcl.
run "no_recipients_means_no_subscriptions_and_nothing_else_changes" {
  command = plan

  variables {
    alert_emails = []
  }

  assert {
    condition     = length(aws_sns_topic_subscription.us_east_1) == 0
    error_message = "An empty alert_emails must create no subscriptions."
  }

  assert {
    condition     = length(aws_cloudwatch_event_rule.us_east_1) == 2 && length(aws_cloudwatch_event_target.us_east_1) == 2
    error_message = "The rules and targets exist regardless of recipients."
  }
}

run "outputs_record_the_rules_and_pending_subscriptions" {
  command = apply

  assert {
    condition = alltrue([
      sort(keys(output.alert_rules)) == sort(["iam", "security-group"]),
      output.alert_rules["iam"].event_names == local.change_alerts["iam"].event_names,
      output.alert_rules["security-group"].name == "security-change-alerts-security-group",
      output.alert_topic_arn == aws_sns_topic.us_east_1.arn,
      sort(keys(output.alert_subscriptions)) == sort(["oncall@example.com", "security@example.com"]),
    ])
    error_message = "Outputs must record every rule's calls, the topic ARN, and one subscription per address."
  }
}

# EventBridge drops an event for good when its retries run out, so an undeliverable alert must
# land somewhere a person can still read it, and something must say that it happened.
run "undelivered_alerts_are_kept_and_alarmed" {
  command = apply

  assert {
    condition = alltrue([
      for key, target in aws_cloudwatch_event_target.us_east_1 : alltrue([
        target.dead_letter_config[0].arn == aws_sqs_queue.us_east_1_dlq.arn,
        target.retry_policy[0].maximum_event_age_in_seconds == 3600,
      ])
    ])
    error_message = "Every target must fall back to the dead-letter queue and stop retrying while the alert still matters."
  }

  assert {
    condition     = aws_sqs_queue.us_east_1_dlq.message_retention_seconds == 1209600
    error_message = "The queue must hold an undelivered alert for the full fourteen days SQS allows."
  }

  # Named rule ARNs rather than a wildcard: another rule in this account must not be able to
  # fill the queue that reports on these alerts.
  assert {
    condition = jsondecode(aws_sqs_queue_policy.us_east_1_dlq.policy).Statement[0].Condition.ArnEquals["aws:SourceArn"] == [
      # Map iteration is alphabetical, which is the order the policy is built in.
      for key in ["iam", "security-group"] : aws_cloudwatch_event_rule.us_east_1[key].arn
    ]
    error_message = "The queue must accept messages only from this framework's own rules."
  }
}

# A detection control that fails silently is the one failure mode it must not have. The alarms
# report to a second topic, because an alarm about a broken alert topic cannot travel through it.
run "the_alert_channel_reports_on_itself" {
  command = apply

  assert {
    condition = alltrue([
      for alarm in concat(
        values(aws_cloudwatch_metric_alarm.us_east_1_failed_invocations),
        [aws_cloudwatch_metric_alarm.us_east_1_undelivered, aws_cloudwatch_metric_alarm.us_east_1_notification_failures],
        ) : alltrue([
          alarm.alarm_actions == toset([aws_sns_topic.us_east_1_health.arn]),
          # These metrics are published only when non-zero, so absent data is the healthy state.
          alarm.treat_missing_data == "notBreaching",
          alarm.threshold == 1,
      ])
    ])
    error_message = "Every health alarm must notify the health topic and treat absent data as healthy."
  }

  assert {
    condition = sort(output.health_alarms) == sort([
      "security-change-alerts-iam-failed-invocations",
      "security-change-alerts-notification-failures",
      "security-change-alerts-security-group-failed-invocations",
      "security-change-alerts-undelivered",
    ])
    error_message = "Three kinds of failure are watched: a rule that cannot deliver, an alert left undelivered, and a notification SNS could not send."
  }

  assert {
    condition = alltrue([
      # The mock hands every topic the same ARN, so identity is asserted on the real names.
      aws_sns_topic.us_east_1_health.name == "security-change-alerts-health",
      aws_sns_topic.us_east_1_health.name != aws_sns_topic.us_east_1.name,
      aws_sns_topic.us_east_1_health.kms_master_key_id == aws_kms_key.us_east_1.key_id,
      sort(keys(aws_sns_topic_subscription.us_east_1_health)) == sort(var.alert_emails),
    ])
    error_message = "The health topic must be a second encrypted topic carrying the same recipients."
  }

  assert {
    condition = contains(jsondecode(aws_kms_key.us_east_1.policy).Statement, {
      Sid       = "CloudWatchPublishesThroughTheKey"
      Effect    = "Allow"
      Principal = { Service = "cloudwatch.amazonaws.com" }
      Action    = ["kms:GenerateDataKey*", "kms:Decrypt"]
      Resource  = "*"
    })
    error_message = "The key must admit CloudWatch, or the alarms cannot publish to the encrypted health topic."
  }
}
