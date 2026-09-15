mock_provider "aws" {
  alias = "us_east_1"

  # The key policy names the account root, so the identity lookup has to return an account-shaped
  # value rather than a random string.
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = join("", ["123456", "789012"])
    }
  }

  # The subscription, the topic policy and the target all validate the topic ARN's shape before
  # a mocked apply, so the mock has to return an ARN rather than a random string.
  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:us-east-1:${join("", ["123456", "789012"])}:security-change-alerts"
    }
  }
}

variables {
  repository    = "nwarila-platform/aws-cloudwatch-framework"
  repository_id = "123456789"
  commit_sha    = "0123456789abcdef0123456789abcdef01234567"
  run_id        = "42"
  environment   = "test"
  alert_emails  = ["security@example.com", "oncall@example.com"]
}

# The rule IS the alert. Every write call that counts is named here, as an exact list, so a
# widening or narrowing of what gets an email is visible as a test diff and nowhere else.
run "security_group_rule_matches_exactly_the_documented_write_calls" {
  command = plan

  assert {
    condition = jsondecode(aws_cloudwatch_event_rule.us_east_1["security-group"].event_pattern) == {
      source        = ["aws.ec2"]
      "detail-type" = ["AWS API Call via CloudTrail"]
      detail = {
        eventSource = ["ec2.amazonaws.com"]
        eventName = [
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
    }
    error_message = "The security-group rule must match exactly the nine EC2 security group write calls, and nothing else."
  }
}

run "iam_role_rule_matches_exactly_the_documented_write_calls" {
  command = plan

  assert {
    condition = jsondecode(aws_cloudwatch_event_rule.us_east_1["iam-role"].event_pattern) == {
      source        = ["aws.iam"]
      "detail-type" = ["AWS API Call via CloudTrail"]
      detail = {
        eventSource = ["iam.amazonaws.com"]
        eventName = [
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
    error_message = "The iam-role rule must match exactly the fifteen IAM role write calls, and nothing else."
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
    condition     = sort(keys(aws_cloudwatch_event_rule.us_east_1)) == sort(["iam-role", "security-group"])
    error_message = "Exactly two change alerts exist: iam-role and security-group."
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

# The email quotes these fields and nothing else; a renamed placeholder would render literally
# in every alert.
run "the_email_quotes_the_documented_fields" {
  command = plan

  assert {
    condition = alltrue([
      for key, target in aws_cloudwatch_event_target.us_east_1 : alltrue([
        sort(keys(target.input_transformer[0].input_paths)) == sort([
          "account", "eventId", "eventName", "principal", "region", "requestParameters", "sourceIp", "time",
        ]),
        alltrue([
          for name in keys(target.input_transformer[0].input_paths) :
          strcontains(target.input_transformer[0].input_template, "<${name}>")
        ]),
        strcontains(target.input_transformer[0].input_template, local.change_alerts[key].headline),
        strcontains(target.input_transformer[0].input_template, "security-change-alerts-${key}"),
      ])
    ])
    error_message = "Every input path must be quoted in the template alongside the alert's headline and rule name."
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

# The bootstrap state: rules and topic exist, nobody is subscribed, nothing is delivered.
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
      sort(keys(output.alert_rules)) == sort(["iam-role", "security-group"]),
      output.alert_rules["iam-role"].event_names == local.change_alerts["iam-role"].event_names,
      output.alert_rules["security-group"].name == "security-change-alerts-security-group",
      output.alert_topic_arn == aws_sns_topic.us_east_1.arn,
      sort(keys(output.alert_subscriptions)) == sort(["oncall@example.com", "security@example.com"]),
    ])
    error_message = "Outputs must record every rule's calls, the topic ARN, and one subscription per address."
  }
}
