# ADR-0002: Alert on What a Person Will Act On

| Field            | Value                                                                       |
| ---------------- | --------------------------------------------------------------------------- |
| ID               | ADR-0002                                                                    |
| Scope            | Repository-specific                                                         |
| Status           | Accepted                                                                    |
| Decision-subject | Which changes raise an email, which principals are exempt, and what the message contains. |
| Date accepted    | 2026-09-16                                                                  |
| Date             | 2026-09-16                                                                  |
| Last reviewed    | 2026-09-16                                                                  |
| Authors          | Nick Warila (@NWarila)                                                      |
| Decision-makers  | Nick Warila (sole portfolio maintainer)                                     |
| Consulted        | Two independent audits of the first implementation.                         |
| Informed         | Framework maintainers.                                                      |
| Reversibility    | High                                                                        |
| Review-by        | 2027-03-16                                                                  |

## TL;DR

The alerts cover the calls that actually change authorisation, including managed-policy versions;
the deploy pipelines are exempt from the security-group alert only; the message is JSON because
EventBridge requires it; and every pattern is proven against EventBridge before an apply.

## Context and Problem Statement

The first implementation was audited twice before it ever deployed. Four things it got wrong or
left open are settled here.

**Volume.** Thirty days of CloudTrail in the deployment account held 28,175 events matching the
alerts, nearly all of them deploy pipelines rewriting security groups on every run. At roughly
940 emails a day per recipient, nobody reads any of them, and an alert nobody reads is not a
control.

**Coverage.** The IAM alert watched role calls only. A principal holding `iam:CreatePolicyVersion`
on a customer-managed policy that is attached to a privileged role can grant that role anything
by publishing a new default version, with no role-level event at all. `AcquireRole` likewise
creates a role from a role template without emitting `CreateRole`. The alert's own description
claimed to cover a role's permissions, and did not.

**Message format.** The message was multi-line prose. EventBridge parses a target's input
template as JSON and rejects anything else, so the first apply would have failed at `PutTargets`
and left two enabled rules with no target. Separately, a JSON object referenced from inside a
string has its internal quotes stripped, so the request detail would have arrived unreadable even
if the template had been accepted.

**Region.** Security-group events are recorded in the region of the call. One region is watched.

## Decision

- **Alert on the calls that change authorisation.** The IAM alert covers role calls, managed
  policy and policy-version calls, `AcquireRole`, and instance-profile attachment. The
  security-group alert covers the eleven EC2 write calls, including both VPC association calls.
- **Exempt the deploy pipelines from the security-group alert, and nothing else.** The exemption
  is a list of role names. It never applies to IAM. It is written as two branches, so an event
  that carries no assumed-role identity keeps matching; a bare exclusion on a nested field would
  have dropped root-user and service-made changes along with the pipelines.
- **Send JSON.** The template carries the headline, the account, the region, the call, the time
  and the rule, plus the whole original event as a JSON value. Only fields present on every
  API-call event are quoted individually, because a path that is absent at runtime is dropped
  from the rendered message and would leave it malformed.
- **Keep one region, and make it a control.** The estate is confined to the supported region by
  an account-level restriction rather than by convention. Without that restriction this is a gap,
  and the invariants say so.
- **Prove patterns against EventBridge.** Fixtures per alert, run against the saved plan on every
  deploy. A mocked test cannot tell what a pattern matches, and the exemption is exactly the kind
  of change that looks right and silently drops events.

## Consequences

- A stolen pipeline credential can change a security group without raising an email. That is a
  named residual in the threat model, and the change is still in CloudTrail.
- The IAM alert is noisier than a role-only alert, which is the point: those calls are the
  quietest way to widen access.
- Adding an alert now means adding fixtures for it, which is a deliberate cost on every future
  alert.
- The email is JSON rather than prose. It is readable on a phone, but it is not a sentence.
