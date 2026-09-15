# ADR-0001: Alert From EventBridge, Not Log Metric Filters

| Field            | Value                                                                       |
| ---------------- | --------------------------------------------------------------------------- |
| ID               | ADR-0001                                                                    |
| Scope            | Repository-specific                                                         |
| Status           | Accepted                                                                    |
| Decision-subject | How a security group or IAM role change becomes an email.                   |
| Date accepted    | 2026-09-15                                                                  |
| Date             | 2026-09-15                                                                  |
| Last reviewed    | 2026-09-15                                                                  |
| Authors          | Nick Warila (@NWarila)                                                      |
| Decision-makers  | Nick Warila (sole portfolio maintainer)                                     |
| Consulted        | Independent architecture review.                                            |
| Informed         | Framework maintainers.                                                      |
| Reversibility    | Medium                                                                      |
| Review-by        | 2027-03-15                                                                  |

## TL;DR

Each alert is an EventBridge rule matching the CloudTrail record of a write call, targeting one
KMS-encrypted SNS topic with an input transformer that renders a readable email. The CloudTrail
trail the rules depend on is a prerequisite the deploy proves, not a resource this repository
manages. The CIS Benchmark pattern of a trail delivering to CloudWatch Logs with metric filters
and alarms is not used.

## Context and Problem Statement

The objective is an email to named recipients whenever a security group or an IAM role changes,
from a framework that stays small enough to read in one sitting. Two designs were compared.

The CIS AWS Foundations Benchmark (section 4) monitors these changes with a trail delivering to
a CloudWatch Logs group, a metric filter per control, an alarm per filter, and an SNS topic. It
is the pattern compliance tooling looks for. Its email is an alarm notification: it says an
alarm fired in a region and nothing about who did what. It also requires the trail to deliver
to Logs, which is ingestion cost on every management event in the account whether alerted on
or not.

EventBridge receives every write management event from CloudTrail while a logging trail exists
(EventBridge User Guide, "AWS service events delivered via AWS CloudTrail"). A rule matches by
exact `eventName`, and an input transformer renders the principal, the call, the source address,
the time, and the request parameters into the message. There is no Logs group, no filter, and
no alarm; the resource count is a key, a topic, its policy, the subscriptions, and one rule and
target per alert.

## Decision

- Alert from EventBridge. Each alert is an exact list of write calls, asserted by test.
- Publish to one SNS topic encrypted with a customer managed key, because the AWS-managed SNS
  key cannot admit EventBridge and Security Hub expects encryption at rest. The key policy
  reproduces the SNS developer guide's statement for event sources verbatim, which carries no
  source condition because the guide states one is unsupported on this path.
- Do not manage the trail. The account is expected to have one; creating a second would
  duplicate global service events and cost storage for no new information. The deploy
  workflow proves a logging trail covers the region before it touches state, so a missing
  trail fails loudly with its cause named rather than applying a silent rule.
- Alert on every principal, including the fleet's own pipelines, until real volume has been
  observed. An exemption list is a later, deliberate change.

## Consequences

- The email arrives under SNS's fixed subject with the topic display name as sender; the
  headline is the first body line. A per-alert subject needs a function between rule and
  topic and is deferred until it is wanted.
- CIS controls 4.4 and 4.10 are not satisfied by this repository's resources as the benchmark
  phrases them. If benchmark evidence is required, the metric-filter layer can be added beside
  this one; it does not replace it.
- Every pipeline deploy in the fleet emails. If that proves too loud, the fix is a principal
  exemption in the event pattern, recorded as its own decision.
