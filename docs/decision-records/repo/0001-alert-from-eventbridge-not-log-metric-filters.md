# ADR-0001: Alert From EventBridge, Not Log Metric Filters

| Field            | Value                                                                       |
| ---------------- | --------------------------------------------------------------------------- |
| ID               | ADR-0001                                                                    |
| Scope            | Repository-specific                                                         |
| Status           | Accepted                                                                    |
| Decision-subject | How a security group, IAM, or CloudTrail change becomes an email.           |
| Date accepted    | 2026-09-15                                                                  |
| Date             | 2026-09-24                                                                  |
| Last reviewed    | 2026-09-24                                                                  |
| Authors          | Nick Warila (@NWarila)                                                      |
| Decision-makers  | Nick Warila (sole portfolio maintainer)                                     |
| Consulted        | Independent architecture review.                                            |
| Informed         | Framework maintainers.                                                      |
| Reversibility    | Medium                                                                      |
| Review-by        | 2027-03-15                                                                  |

## TL;DR

Each alert is an EventBridge rule matching the CloudTrail record of a write call, targeting one
KMS-encrypted SNS topic with an input transformer that renders a readable email. The CIS
Benchmark pattern of a trail delivering to CloudWatch Logs with metric filters and alarms is not
used. The trail the rules depend on was first treated as a prerequisite only;
[ADR-0003](0003-own-the-trail-behind-a-switch.md) now lets a deployment create it.

## Context and Problem Statement

The objective is an email to named recipients whenever a security group or an IAM role changes,
from a framework that stays small enough to read in one sitting.

The CIS AWS Foundations Benchmark (section 4) monitors these changes with a trail delivering to
a CloudWatch Logs group, a metric filter per control, an alarm per filter, and an SNS topic. It
is the pattern compliance tooling looks for. Its email is an alarm notification: it says an
alarm fired in a region and nothing about who did what. It also requires the trail to deliver
to Logs, which is ingestion cost on every management event in the account whether alerted on
or not.

EventBridge receives every write management event from CloudTrail while a logging trail exists
(EventBridge User Guide, "AWS service events delivered via AWS CloudTrail"). A rule matches by
exact `eventName`, and an input transformer renders the principal, the call, the source address,
the time, and the request parameters into the message. There is no Logs group and no filter;
the resource set is a key, a topic, its policy, the subscriptions, one rule and target per
alert, and the channel's own health: a second topic, a dead-letter queue, and the alarms that
report to it.

## Decision Drivers

1. **The email must say who did what.** A recipient acts on the principal, the call and the
   request, not on the fact that an alarm fired.
2. **Small enough to read.** Every resource is one more thing a reviewer must understand.
3. **No cost for events nobody alerts on.** Ingesting every management event into Logs to alert
   on a handful is spend without a reader.
4. **A broken prerequisite fails loudly.** Rules that depend on a trail must not deploy silently
   into an account where they can never fire.

## Considered Options

1. **EventBridge rules on CloudTrail events (chosen).** One rule and target per alert, matching
   exact write calls, publishing to one encrypted topic.
2. **CloudTrail to CloudWatch Logs with metric filters and alarms.** The CIS section 4 pattern.

## Decision Outcome

Chosen option: **Option 1, EventBridge rules on CloudTrail events.**

- Alert from EventBridge. Each alert is an exact list of write calls, asserted by test.
- Publish to one SNS topic encrypted with a customer managed key, because the AWS-managed SNS
  key cannot admit EventBridge and Security Hub expects encryption at rest. The key policy
  reproduces the SNS developer guide's statement for event sources verbatim, which carries no
  source condition because the guide states one is unsupported on this path.
- Treat a logging trail as something the deploy proves, so a missing trail fails loudly with its
  cause named rather than applying a rule that never fires. Before applying, the deploy proves
  either that a covering trail exists or, when the plan creates one, that no trail does; after
  applying, it proves coverage either way. Whether
  the framework also creates that trail is decided in
  [ADR-0003](0003-own-the-trail-behind-a-switch.md).
- Which principals raise an email is decided in
  [ADR-0002](0002-alert-on-what-a-person-will-act-on.md).

### Previous decisions

Until 2026-09-22 this section also read:

- "Do not manage the trail. The account is expected to have one; creating a second would
  duplicate global service events and cost storage for no new information."
- "Alert on every principal, including the fleet's own pipelines, until real volume has been
  observed. An exemption list is a later, deliberate change."

Until 2026-09-24 the Decision-subject read "How a security group or IAM role change becomes an
email", and the resource set was described as "a key, a topic, its policy, the subscriptions,
and one rule and target per alert", before the channel reported on itself.

## Pros and Cons of the Options

### Option 1: EventBridge rules on CloudTrail events

- **Good, because** the message carries the principal, the call, the source address, the time
  and the request.
- **Good, because** the resource set is a key, a topic, its policy, the subscriptions, one rule
  and target per alert, and the few resources that report on the channel itself.
- **Good, because** it adds no Logs ingestion; unalerted events cost nothing here.
- **Bad, because** it does not produce the metric filters and alarms CIS section 4 names, so
  benchmark tooling will not recognise it.
- **Bad, because** SNS fixes the email subject; a per-alert subject needs a function between rule
  and topic.

### Option 2: CloudTrail to CloudWatch Logs with metric filters and alarms

- **Good, because** it is the pattern compliance tooling checks for.
- **Bad, because** the email says only that an alarm fired in a region.
- **Bad, because** the trail must deliver every management event to Logs, which is ingestion
  cost whether or not an alert reads it.
- **Bad, because** each control needs a Logs group, a filter and an alarm on top of the topic.

## Confirmation

1. `terraform/tests/alerts.tftest.hcl` asserts each rule's exact `eventName` list, that every
   rule is `ENABLED` on the `default` bus, that every rule publishes to the one encrypted topic,
   and that the key admits EventBridge.
2. `tools/check_cloudtrail.sh` runs before the apply, where it fails when the plan creates no
   trail and none covers the region, or creates one and any trail already exists, and again after
   it, where it fails without coverage, as the runner protocol requires.
3. `docs/reference/invariants.md` states the exact-list, encryption and key-policy rules.

## Consequences

### Positive

- An email tells the recipient who changed what, from where, and with which request.
- The framework stays a few resources per alert, with no Logs group to size or pay for.

### Negative

- CIS controls 4.4 and 4.10 are not satisfied by this repository's resources as the benchmark
  phrases them.
- The email arrives under SNS's fixed subject with the topic display name as sender; the
  headline is the first body line.

### Neutral

- If benchmark evidence is required, the metric-filter layer can be added beside this one; it
  does not replace it.
- A per-alert subject is deferred until it is wanted.

## Assumptions

1. CloudTrail keeps delivering write management events to the default EventBridge bus while a
   logging trail exists.
2. SNS keeps rejecting EventBridge publishes to a topic encrypted with the AWS-managed key.
3. Recipients read email; a different channel would be a new decision.

## Supersedes

None.

## Superseded by

None (current).

## Implementing PRs

- nwarila-platform/aws-monitoring-terraform-framework#1, "feat: email security group and IAM
  permission changes": the rules, the encrypted topic, and the pre-apply trail proof.
- nwarila-platform/aws-monitoring-terraform-framework#3, "feat: deploy one commit to any account
  by changing providers.tf alone": the key, topic and rule ARNs take their partition and region
  from the provider.
- nwarila-platform/aws-monitoring-terraform-framework#13, "feat(alerts): email trail changes, and
  close the whole-project audit": the third rule, for trail changes, and the
  channel's own health resources named in the resource set.

## Related ADRs

- [ADR-0002](0002-alert-on-what-a-person-will-act-on.md) decides which calls and principals
  raise an email, replacing this record's original "alert on every principal".
- [ADR-0003](0003-own-the-trail-behind-a-switch.md) revises this record's premise that the trail
  is never managed here. It is a partial revision, not a supersession.

## Compliance Notes

This decision chooses an alerting mechanism; it is not a claim of compliance.

| Framework              | Control / Practice ID | Relationship                                                                    |
| ---------------------- | --------------------- | ------------------------------------------------------------------------------- |
| CIS AWS Foundations    | 4.4, 4.10             | Not met as phrased: the benchmark names metric filters and alarms, not EventBridge rules. |
| NIST SP 800-53 Rev. 5  | AU-6, SI-4            | The alerts can support review and monitoring of security-relevant changes.       |

## Changelog

| Date       | Change                                                     | Reason                                                   | Author/Role          | Body-diff? |
| ---------- | ---------------------------------------------------------- | -------------------------------------------------------- | -------------------- | ---------- |
| 2026-09-15 | Accepted.                                                  | Record the alerting design.                              | Portfolio maintainer | Yes        |
| 2026-09-22 | Restructured to the org ADR schema; added drivers, options, confirmation, assumptions and compliance notes. | Bring the record to the required schema. | Portfolio maintainer | Yes |
| 2026-09-22 | Recorded that ADR-0003 revised the "do not manage the trail" premise; prior text kept under Previous decisions. | The premise that every account already has a trail did not hold. | Portfolio maintainer | Yes |
| 2026-09-22 | Recorded that ADR-0002 replaced "alert on every principal"; prior text kept under Previous decisions. | Pipelines are exempt from the security-group alert.     | Portfolio maintainer | Yes        |
| 2026-09-24 | Decision-subject and resource set now include the CloudTrail alert, the health topic, the queue and the alarms; prior text kept under Previous decisions. | The record described fewer resources than the framework declares. | Portfolio maintainer | Yes |
| 2026-09-24 | Implementing PRs: added #13. | Record the pull request that carried this record's 2026-09-24 edits. | Portfolio maintainer | Yes |
