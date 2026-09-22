# Architecture

## Module Boundary

This repository is a Terraform root module for one pre-existing AWS account. It owns the alert
channel, the rules that feed it, and, when `manage_trail` is set, the CloudTrail trail those
rules read. It does not own account bootstrap, IAM, OIDC, or remote state.

The module declares:

- Channel: one `aws_kms_key` with its `aws_kms_alias`, one `aws_sns_topic` encrypted with that
  key, its `aws_sns_topic_policy`, and one `aws_sns_topic_subscription` per recipient.
- Alerts: one `aws_cloudwatch_event_rule` per change alert and one `aws_cloudwatch_event_target`
  wiring it to the topic through an input transformer.
- Health: a second `aws_sns_topic` with the same recipients, an `aws_sqs_queue` holding alerts
  that could not be delivered, and three `aws_cloudwatch_metric_alarm` resources reporting to
  the health topic.
- Source of events, optional: an `aws_cloudtrail` trail and the closed S3 bucket it writes to,
  created only when `manage_trail` is set.

## How an alert reaches an inbox

1. Someone calls a security group or IAM role write API. CloudTrail records the call. IAM is a
   global service, so CloudTrail records its calls in the partition's global-service region:
   `us-east-1` in the commercial partition, `us-gov-west-1` in GovCloud. Security group calls are
   recorded in the region they target. The provider must therefore target the global-service
   region, and the workloads must live there too; the IAM rule refuses any other region at plan.
2. Because a logging trail exists, CloudTrail hands the record to the default EventBridge bus as
   an `AWS API Call via CloudTrail` event. Without a trail there is no event, which is why the
   deploying runner proves a trail before applying. A rule in the default `ENABLED` state matches
   write management events, which is the whole category this framework alerts on.
3. The rule whose `eventName` list names the call matches. The security-group rule additionally
   excludes the deploy pipelines named in `exempt_pipeline_roles`, and that exclusion is written
   as two branches so that an event carrying no assumed-role identity still matches. Its target
   is the topic, and the input transformer renders the event as a JSON message carrying the
   headline, the account, the region, the call, the time, the rule, and the whole original event.
4. EventBridge publishes through the topic's KMS key, which the key policy admits, and SNS
   emails every confirmed subscription.

## Inputs And Locals

Consumers set `environment` and `alert_emails` in the committed `terraform.tfvars`; the deploy
workflow supplies the four identity variables on the command line. The alerts themselves are
framework-owned: `local.change_alerts` in `locals.tf` names each alert's CloudTrail source and
the exact write calls that count. Adding an alert is adding an entry there and asserting its
call list in `tests/alerts.tftest.hcl`. Adding a region is a code change across providers,
locals, resources and tests, as it is in every framework of this type.

## Why the email is JSON

EventBridge parses a target's input template as JSON and rejects anything else, so the message is
a JSON object rather than prose. That is also what keeps `requestParameters` readable: a JSON
object referenced from inside a string has its quotes stripped, while the same object placed as a
value survives intact. The template therefore quotes only fields every CloudTrail API-call event
carries and attaches the rest of the record through the reserved whole-event value, because a
path that is absent at runtime is dropped and would leave the message malformed.

EventBridge sets no per-message subject when it publishes to SNS, so every alert arrives under
SNS's fixed subject with the topic's display name as the sender. The headline is the first field
of the body instead. A per-alert subject would need a function between the rule and the topic,
which is more machinery than the alert is worth today.

## When delivery fails

EventBridge retries a failed publish and then drops the event for good, so a broken key policy or
a deleted topic would lose security changes with nothing said. Three things prevent that. The
target falls back to a dead-letter queue that holds an undelivered alert for fourteen days. The
retry window is one hour rather than the default day, because an alert that arrives tomorrow has
already failed. Four alarms watch the three ways delivery breaks, one per rule for the first:
EventBridge failing to deliver to the topic, an alert sitting in the queue, and SNS accepting a
publish and then failing to reach a recipient.

The alarms report to a second topic carrying the same recipients. That separation is the point:
an alarm about a broken alert topic cannot be delivered through that topic. Each of those metrics
is published only when it is non-zero, so the alarms treat missing data as healthy.

## Proving what a pattern matches

A mocked test can assert what a pattern contains; only EventBridge can say what it matches. The
deploy runs `tools/check_event_patterns.sh` against the saved plan, testing each rule with the
fixtures under `tools/fixtures/events/`, whose names state the answer each must get. A pattern
that stops matching a human change, or starts matching a read call, fails the deploy before
anything reaches the account.

## Outputs

The outputs record the topic ARN, every rule with the calls it matches, and each subscription
with whether it is still pending confirmation. Identity is not re-exported: it is on every
resource's tags.
