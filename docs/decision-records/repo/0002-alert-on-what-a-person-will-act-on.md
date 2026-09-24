# ADR-0002: Alert on What a Person Will Act On

| Field            | Value                                                                       |
| ---------------- | --------------------------------------------------------------------------- |
| ID               | ADR-0002                                                                    |
| Scope            | Repository-specific                                                         |
| Status           | Accepted                                                                    |
| Decision-subject | Which changes raise an email, which principals are exempt, and what the message contains. |
| Date accepted    | 2026-09-16                                                                  |
| Date             | 2026-09-24                                                                  |
| Last reviewed    | 2026-09-24                                                                  |
| Authors          | Nick Warila (@NWarila)                                                      |
| Decision-makers  | Nick Warila (sole portfolio maintainer)                                     |
| Consulted        | Independent audits.                                                         |
| Informed         | Framework maintainers.                                                      |
| Reversibility    | High                                                                        |
| Review-by        | 2027-03-16                                                                  |

## TL;DR

The alerts cover the calls that actually change authorisation, including managed-policy versions,
and the calls that stop or reshape the trail every alert here reads. Deploy pipelines are exempt
from the security-group alert only, named by exact role name or by a `*` pattern that follows the
fleet's naming convention, and never in a way that can reach the roles people sign in through.
The message is JSON because EventBridge requires it, and every pattern, including the exemption
against real role names, is proven against EventBridge before an apply.

## Context and Problem Statement

Five things are settled here, including how the exemption keeps up with a growing fleet of
pipelines.

**Volume.** An account whose deploy pipelines rewrite security groups on every run produces far
more matching events than a person can read, and an alert nobody reads is not a control.

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

**The trail itself.** Every alert here reads one CloudTrail trail. Stopping it, deleting it, or
narrowing what it records silences all of them at once, with no email, because the rules that
would have emailed depend on the thing that was stopped.

**Keeping the exemption current.** An exact list of pipeline roles falls behind silently: each
pipeline added to the fleet alerts on every run until someone remembers to add its role. A
pattern keeps up, but a careless pattern can also exempt people, and a pattern proven only
against a name derived from itself proves nothing about the roles it is meant to cover.

## Decision Drivers

1. **Every email is worth reading.** Volume a person ignores disables the control.
2. **Silence must be narrow.** An exemption may hide automation, never people, never IAM, and
   never events that carry no assumed-role identity.
3. **Coverage follows authority, not resource type.** Any call that widens a role's permissions
   alerts, whatever resource it touches.
4. **The exemption keeps up without upkeep.** A new pipeline that follows the naming convention
   must not start emailing.
5. **Proof by the matcher that runs.** Only EventBridge can say what a pattern matches.

## Considered Options

1. **Alert on every principal.** No exemption.
2. **Exempt pipelines from every alert.**
3. **Exempt pipelines from the security-group alert only, by exact role name.**
4. **Exempt pipelines from the security-group alert only, by exact name or `*` pattern, guarded
   and proven against real role names (chosen).**

## Decision Outcome

Chosen option: **Option 4.**

- **Alert on the calls that change authorisation.** The IAM alert covers role calls, managed
  policy and policy-version calls, `AcquireRole`, and instance-profile attachment. The
  security-group alert covers the eleven EC2 write calls, including both VPC association calls.
- **Alert when the trail is stopped or changed** (2026-09-24). A third alert matches
  `StopLogging`, `DeleteTrail`, `UpdateTrail` and `PutEventSelectors`, and nobody is exempt from
  it. AWS's Well-Architected guidance names watching `cloudtrail:StopLogging` through EventBridge
  as the control for a disabled trail, and states that a stopped trail's final digest can cover
  events up to and including the `StopLogging` call. The alert has a limit: CloudTrail accepts
  those four calls only in a trail's home region, so a multi-region trail homed elsewhere can be
  stopped without an email, and an organization trail's calls are recorded in the management
  account, where a member account's rule never sees them. The deployment guide has the operator
  confirm the trail's home region and that it is not an organization trail, and the threat model
  carries the residual.
- **Exempt the deploy pipelines from the security-group alert, and nothing else.**
  `exempt_pipeline_roles` takes exact role names or patterns using `*`, matched with
  EventBridge's `anything-but` wildcard; an entry without `*` still matches exactly, and the
  default exempts nobody. It never applies to IAM, so creating a role whose name matches still
  alerts. It is written as two branches, so an event that carries no assumed-role identity keeps
  matching; a bare exclusion on a nested field would have dropped root-user and service-made
  changes along with the pipelines.
- **Keep people out of the exemption.** Every entry must begin with a literal name, and the text
  before its first `*` must neither begin with nor lead into `AWSReservedSSO_`, the prefix of the
  roles people sign in through. Consecutive wildcards, which EventBridge refuses, are rejected.
- **Send JSON.** The template carries the headline, the account, the region, the call, the time
  and the rule, plus the whole original event as a JSON value. Only fields present on every
  API-call event are quoted individually, because a path that is absent at runtime is dropped
  from the rendered message and would leave it malformed.
- **Keep one region, and make it a control.** A deployment's account must be confined to the
  supported region by an account-level restriction rather than by convention. Without that
  restriction this is a gap, and the invariants say so.
- **Prove patterns against EventBridge.** Fixtures per alert, run against the saved plan on every
  deploy. A deployment that exempts anyone passes real role names the exemption must cover to
  `tools/check_event_patterns.sh`, and each must prove exempt; a plan that exempts roles without
  a named role, or names roles while exempting nobody, fails.

### Previous decisions

Until 2026-09-21 the exemption bullet read: "The exemption is a list of role names. It never
applies to IAM." Entries were matched exactly with `anything-but`, and there was no sign-in-role
guard or real-role proof.

Until 2026-09-24 the alerts covered security groups and IAM only; the trail they read was proven
to exist and to log, and its stopping went unreported.

## Pros and Cons of the Options

### Option 1: Alert on every principal

- **Good, because** nothing is ever silenced.
- **Bad, because** pipeline changes bury the ones a person must see, so none are read.

### Option 2: Exempt pipelines from every alert

- **Good, because** it is the quietest.
- **Bad, because** an IAM change is the quietest way to widen access, and a pipeline credential
  is exactly what an attacker would use to make one.

### Option 3: Exempt from the security-group alert only, by exact role name

- **Good, because** each entry names precisely one role, so nothing is exempt by accident.
- **Bad, because** the list falls behind every time the fleet gains a pipeline, and nothing says
  so except the email it was meant to stop.

### Option 4: Exact name or `*` pattern, guarded, proven against real roles

- **Good, because** one entry covers every pipeline that follows the naming convention,
  including ones added later.
- **Good, because** the leading-literal and sign-in-prefix guards stop a pattern reaching people.
- **Good, because** proving real role names catches a misspelt pattern that would exempt no one.
- **Bad, because** a role created later with a matching name is silenced for security-group
  changes; its creation still raises the IAM alert.
- **Bad, because** each deployment must supply at least one real role name to the proof.

## Confirmation

1. `terraform/tests/alerts.tftest.hcl` asserts all three exact call lists, that the exemption
   still matches an identity with no session, that neither the IAM nor the CloudTrail alert
   carries one, and that an empty list adds no exemption clause.
2. `terraform/tests/validation.tftest.hcl` accepts a pattern and rejects an ARN, a duplicate, an
   all-wildcard or leading-wildcard pattern, patterns that reach `AWSReservedSSO_`, and `**`.
3. `tools/check_event_patterns.sh` tests every planned pattern against EventBridge with the
   fixtures under `tools/fixtures/events/`, substituting each named real role.
4. `terraform/tests/alerts.tftest.hcl` asserts the message template is JSON.
5. `docs/reference/invariants.md` states the exemption, template and region rules.

## Consequences

### Positive

- An email means a person or an unexpected principal changed something.
- Policy-version and role-template changes alert, closing the quietest routes to wider access.
- Stopping or narrowing the trail, the one act that silences every other alert, is itself
  emailed.
- New pipelines inherit the exemption by following the naming convention.

### Negative

- A stolen pipeline credential can change a security group without raising an email. That is a
  named residual in the threat model, and the change is still in CloudTrail.
- Adding an alert means adding fixtures for it, which is a deliberate cost on every future alert.

### Neutral

- The IAM alert is noisier than a role-only alert, which is the point.
- The email is JSON rather than prose. It is readable on a phone, but it is not a sentence.

## Assumptions

1. Pipeline roles follow a naming convention distinct from human sign-in roles.
2. Human sign-in roles carry the `AWSReservedSSO_` prefix.
3. EventBridge keeps supporting `wildcard` inside `anything-but`.
4. The account denies resource creation outside the supported region.

## Supersedes

None.

## Superseded by

None (current).

## Implementing PRs

- nwarila-platform/aws-monitoring-terraform-framework#1, "feat: email security group and IAM
  permission changes": the call lists, the exact-name exemption, the JSON message, the fixtures.
- nwarila-platform/aws-monitoring-terraform-framework#3, "feat: deploy one commit to any account
  by changing providers.tf alone": `exempt_pipeline_roles` defaults to exempting nobody.
- nwarila-platform/aws-monitoring-terraform-framework#4, "feat(alerts): exempt pipeline roles by
  naming pattern, not by list".
- nwarila-platform/aws-monitoring-terraform-framework#5, "fix(alerts): prove the exemption with
  real role names, and keep people out of it".

## Related ADRs

- [ADR-0001](0001-alert-from-eventbridge-not-log-metric-filters.md) chose EventBridge rules; this
  record replaces its original "alert on every principal".

## Compliance Notes

This decision tunes what the alerts cover; it is not a claim of compliance. The exemption is a
deliberate monitoring gap for named automation, recorded in the threat model, and CloudTrail
keeps the exempt events.

| Framework              | Control / Practice ID | Relationship                                                                    |
| ---------------------- | --------------------- | ------------------------------------------------------------------------------- |
| NIST SP 800-53 Rev. 5  | SI-4                  | Defines which changes are monitored and which automated principals are excluded. |
| NIST SP 800-53 Rev. 5  | AC-2(4)               | IAM changes alert regardless of principal.                                       |

## Changelog

| Date       | Change                                                     | Reason                                                   | Author/Role          | Body-diff? |
| ---------- | ---------------------------------------------------------- | -------------------------------------------------------- | -------------------- | ---------- |
| 2026-09-16 | Accepted.                                                  | Settle coverage, exemption, message format and region.   | Portfolio maintainer | Yes        |
| 2026-09-21 | Exemption changed from an exact role list to exact names or `*` patterns (PR #4); prior text kept under Previous decisions. | An exact list silently falls behind a growing fleet of pipelines. | Portfolio maintainer | Yes |
| 2026-09-22 | Added the sign-in-role guard and the real-role proof (PR #5). | A pattern could reach sign-in roles, and a pattern proven against itself proved nothing. | Portfolio maintainer | Yes |
| 2026-09-22 | Restructured to the org ADR schema; removed one deployment's measurements from the context; the region decision now speaks of a deployment's account rather than the estate, with its substance unchanged. | Bring the record to the required schema and keep it environment-neutral. | Portfolio maintainer | Yes |
| 2026-09-24 | Added the CloudTrail alert on `StopLogging`, `DeleteTrail`, `UpdateTrail` and `PutEventSelectors`, never exempt, with its home-region limit; prior scope kept under Previous decisions. | Stopping the trail silenced every alert with no email. | Portfolio maintainer | Yes |
