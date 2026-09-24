# ADR-0004: Encrypt With a Supplied Key When One Is Named

| Field            | Value                                                                       |
| ---------------- | --------------------------------------------------------------------------- |
| ID               | ADR-0004                                                                    |
| Scope            | Repository-specific                                                         |
| Status           | Accepted                                                                    |
| Decision-subject | Which KMS key encrypts the alert channel, and who owns it.                  |
| Date accepted    | 2026-09-23                                                                  |
| Date             | 2026-09-24                                                                  |
| Last reviewed    | 2026-09-24                                                                  |
| Authors          | Nick Warila (@NWarila)                                                      |
| Decision-makers  | Nick Warila (sole portfolio maintainer)                                     |
| Consulted        | Independent gate reviews.                                                   |
| Informed         | Framework maintainers.                                                      |
| Reversibility    | Medium                                                                      |
| Review-by        | 2027-09-23                                                                  |

## TL;DR

A deployment may name an existing key by its alias. The framework then encrypts the alert topic
with that key and creates no key, no alias and no key policy, and its deploy role needs only
`kms:DescribeKey`. Naming nothing keeps the original behaviour: the framework creates and owns a
key for the channel. The health topic, which reports on that channel, is encrypted with nothing.

## Context and Problem Statement

ADR-0001 settled that the channel is encrypted with a customer managed key, and the framework
created one. That assumes the deploying role may create keys and write key policies.

Accounts exist where it may not. Where keys are created through a separate approval process, a
role that can call `CreateKey` and `PutKeyPolicy` is the thing the process exists to prevent, and
a framework that insists on creating its own key cannot be deployed there at all.

The channel needs a key it can use. It does not need to be the thing that made it.

## Decision Drivers

- An account whose keys are created outside its pipelines must still be able to deploy the alerts.
- The deploy role should hold the least that works: reading a key is not managing one.
- A key that cannot carry the channel must fail while a person is watching, not after the alerts
  are live and silent.
- What an administrator states must be something they already know, and must not be inferred.
- The deployment that already owns a framework-created key must not have it replaced or deleted.

## Considered Options

1. Always create the key, as before.
2. Always adopt an existing key, and never create one.
3. Adopt a key when its alias is named, and create one otherwise.
4. Accept a key ARN rather than an alias.
5. Resolve the alias with `data.aws_kms_alias`, as the reference framework does.

## Decision Outcome

Chosen: **option 3**, with the alias resolved by `data.aws_kms_key` (rejecting option 5).

- `alert_key_alias` takes an alias name without the `alias/` prefix. Null, the default, creates
  and owns a key exactly as before.
- When a name is given, `data.aws_kms_key` resolves `alias/<name>` with a single `DescribeKey`
  call. The alert topic is encrypted with the key's own identifier, never with the alias, so
  retargeting that alias later moves the topic's encryption at the next plan, visibly, rather
  than silently between plans.
- Postconditions on the lookup refuse a key that is not `SYMMETRIC_DEFAULT`, which SNS cannot use,
  and one that is not `Enabled`. Validation refuses an `aws/` alias, because an AWS-managed key's
  policy cannot be edited to admit EventBridge.
- In that mode the framework writes no key policy, so it does not ask IAM for the deploying role's
  ARN, and the deploy role needs neither `iam:GetRole` nor any KMS management call.
- **The health topic is not encrypted** (2026-09-24). It exists to report that the alert channel
  is broken, and a broken key policy is one of the ways the channel breaks; a report that travels
  through the key it reports on is silenced by the failure it exists to raise. What the topic
  carries is an alarm's name and state. Two alternatives were weighed: a second key of its own,
  which is a further key, policy and grant to protect an alarm name, and leaving the topic on the
  shared key, which is the dependency above. The residual is Security Hub's SNS encryption
  control (`sns-encrypted-kms`) flagging that one topic; see Compliance Notes. A key policy this
  framework writes keeps admitting `cloudwatch.amazonaws.com` for one release after the change,
  because a deployment converging from the shared-key release rewrites the topic and the key
  policy in one apply with nothing ordering the two; the statement is removed in the release after
  every deployment has converged, recorded in the Changelog.

`data.aws_kms_key` rather than the reference's `data.aws_kms_alias` is a deliberate deviation. The
alias data source calls `ListAliases`, an account-wide read, and exposes nothing about the key
itself; this one calls `DescribeKey` alone and exposes the properties the postconditions need.
The consumer's input is the same friendly alias either way.

### Previous decisions

Until 2026-09-24 the key encrypted both topics: the second bullet read "Both topics are encrypted
with the key's own identifier, never with the alias, so retargeting that alias later cannot
silently move where the topics' encryption points", the Assumptions held that a supplied key's
owner keeps its policy admitting `cloudwatch.amazonaws.com`, and the deployment guide required a
supplied key to admit CloudWatch.

## Pros and Cons of the Options

### Option 1: Always create the key

- **Good, because** the framework owns the whole channel and can guarantee rotation and policy.
- **Bad, because** it cannot deploy at all in an account where keys are created by approval.

### Option 2: Always adopt

- **Good, because** the deploy role never holds a KMS management call.
- **Bad, because** every deployment must arrange a key first, including throwaway ones.
- **Bad, because** the existing deployment's key would have to be moved out of Terraform's state
  deliberately, and a careless destroy would schedule its deletion.

### Option 3: Adopt when named, create otherwise

- **Good, because** an account with an approval process and an account without one both deploy.
- **Good, because** the change is additive: no existing value file changes.
- **Neutral, because** two modes exist, though they converge to one resolved key id immediately.
- **Bad, because** the framework can no longer promise rotation or policy in every deployment.

### Option 4: Accept a key ARN

- **Good, because** it is exact, with no resolution step.
- **Bad, because** it drags the account id and partition into a value file that otherwise carries
  neither, and an ARN is not what an administrator calls the key.

### Option 5: Resolve with `data.aws_kms_alias`

- **Good, because** it matches the reference framework's idiom exactly.
- **Bad, because** it needs `kms:ListAliases` on `*`, an account-wide read, for one lookup.
- **Bad, because** it says nothing about the key, so a key that cannot carry the channel is only
  discovered when no alert arrives.

## Confirmation

1. `terraform/tests/alerts.tftest.hcl` asserts that a supplied alias creates no key, no alias and
   no session-context lookup, that the alert topic carries the resolved key's id and the health
   topic no key in either mode, and that the lookup is made by alias. Two runs drive the
   postconditions with an asymmetric key and a key pending deletion.
2. `terraform/tests/validation.tftest.hcl` accepts a bare alias name and rejects an empty one,
   one carrying the `alias/` prefix, an `aws/` name, and an ARN.
3. `terraform/tests/portability.tftest.hcl` renders the supplied-key mode in GovCloud.
4. `docs/reference/runner-protocol.md` states the permissions each mode needs, and
   `docs/how-to/deploy-to-a-new-account.md` states what a supplied key's policy must carry.

## Consequences

### Positive

- An account that forbids key creation in CI can deploy the alerts.
- In that mode the deploy role holds one KMS call, and no IAM call at all.
- A key that could never carry the channel fails at plan, naming what is wrong with it.

### Negative

- The framework cannot promise rotation or a correct key policy for a key it does not own, and no
  data source exposes a key policy for it to check.
- A deployment that switches from an owned key to a supplied one schedules the old key for
  deletion, which makes it unusable immediately; an alert still awaiting delivery at that moment
  is lost.

### Neutral

- Two modes exist in the configuration, but only the key and alias resources branch: everything
  downstream reads one resolved key id.

## Assumptions

- A supplied key's owner keeps its policy admitting `events.amazonaws.com` and the deploy
  role's `kms:DescribeKey`, and keeps the key enabled.
- An alias resolves within the deploying account and region, which KMS guarantees.

## Supersedes

None. This records a decision ADR-0001 left open by assuming the framework would always create the
key.

## Superseded by

None.

## Implementing PRs

- nwarila-platform/aws-monitoring-terraform-framework#11, "feat(alerts): encrypt the channel with
  a key supplied by alias".

## Related ADRs

- [ADR-0001](0001-alert-from-eventbridge-not-log-metric-filters.md) settled that the channel is
  encrypted with a customer managed key; this record decides who creates it.
- [ADR-0003](0003-own-the-trail-behind-a-switch.md) makes the same shape of decision for the
  trail: own it behind a switch, default off.

## Compliance Notes

- AWS Security Hub SNS.1 (`sns-encrypted-kms`, SNS topics encrypted at rest with a KMS key) is
  met by the alert topic in both modes; in supplied-key mode the evidence is the key's own
  configuration rather than this module's. The health topic does not meet it, deliberately, for
  the reason in the Decision Outcome.
- NIST SP 800-53 SC-12 and SC-28: key management moves to the key's owner when one is supplied,
  which is the point of the option for accounts that separate that duty.

## Changelog

| Date       | Change                                      | Reason                                                    | Author/Role                       | Body-diff? |
| ---------- | ------------------------------------------- | --------------------------------------------------------- | --------------------------------- | ---------- |
| 2026-09-23 | Accepted. | An account that creates keys outside CI could not deploy the alerts. | Portfolio maintainer | Yes |
| 2026-09-24 | The health topic is no longer encrypted; prior text kept under Previous decisions. Follow-up: remove the key policy's `CloudWatchPublishesThroughTheKey` statement in the release after every deployment has converged. | A report of a broken key must not depend on that key. | Portfolio maintainer | Yes |
