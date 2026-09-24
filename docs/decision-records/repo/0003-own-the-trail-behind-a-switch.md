# ADR-0003: Own the Trail, Behind a Switch

| Field            | Value                                                                       |
| ---------------- | --------------------------------------------------------------------------- |
| ID               | ADR-0003                                                                    |
| Scope            | Repository-specific                                                         |
| Status           | Accepted                                                                    |
| Decision-subject | Whether this framework creates the CloudTrail trail its alerts depend on.   |
| Date accepted    | 2026-09-16                                                                  |
| Date             | 2026-09-24                                                                  |
| Last reviewed    | 2026-09-24                                                                  |
| Authors          | Nick Warila (@NWarila)                                                      |
| Decision-makers  | Nick Warila (sole portfolio maintainer)                                     |
| Consulted        | Independent audits.                                                         |
| Informed         | Framework maintainers.                                                      |
| Reversibility    | Medium                                                                      |
| Review-by        | 2027-03-16                                                                  |

## TL;DR

The framework creates a multi-region trail with log file validation, writing to its own closed
bucket with a one-year expiry, when `manage_trail` is set. It is off by default, because a second
trail in an account bills every management event twice. This revises the part of
[ADR-0001](0001-alert-from-eventbridge-not-log-metric-filters.md) that treated the trail purely
as a prerequisite.

## Context and Problem Statement

ADR-0001 decided not to manage the trail, on the premise that every account would already have
one. That premise does not hold: an account can have no trail at all, organization trails
included. There the alerts depend on something nobody owns, and a deploy that only checks for a
trail can do nothing but fail.

Creating one unconditionally is also wrong. AWS delivers one copy of an account's management
events to S3 free and bills every copy after that. An organization trail places a copy of itself
in each member account, so an account that gains one later would pay twice for the same records
if this framework had created its own.

## Decision Drivers

1. **The alerts need a trail someone owns.** An unowned prerequisite is a permanent failure.
2. **Never pay twice.** A second copy of management events adds cost and no information.
3. **The audit record outlives the alerts.** Losing it is worse than any alert this framework
   raises.
4. **The safe choice needs no thought.** Omitting the setting must not create cost.

## Considered Options

1. **Assume a trail exists and prove it before the apply.** ADR-0001's original premise.
2. **Always create a trail.**
3. **Create a trail behind a per-deployment switch, off by default, with a duplicate-trail guard
   (chosen).**

## Decision Outcome

Chosen option: **Option 3.**

- A `manage_trail` variable, set per deployment, decides whether the trail is created. It
  defaults to false, because creating a trail is the costly mistake and omitting the setting must
  never make it.
- When set, the framework creates a multi-region trail including global service events, with log
  file validation on, writing to a bucket it owns with public access blocked, ACLs disabled,
  S3-managed encryption, and a 365-day expiry.
- The trail and its bucket carry `prevent_destroy`. Losing them removes the account's audit
  record.
- The deploy decides from the saved plan which check to run. If the plan creates a trail, no
  other covering trail may already exist. If it does not, a covering trail must already exist.
  After the apply, a covering trail must exist either way. A pipeline that runs only Terraform
  cannot make these checks; an operator runs `tools/check_cloudtrail.sh` by hand before each
  account's first apply.

### Previous decisions

Until 2026-09-21 the first bullet read: "It has no default: a deployment states which case it is
in."

## Pros and Cons of the Options

### Option 1: Assume a trail exists and prove it

- **Good, because** the framework owns no account-wide audit infrastructure.
- **Bad, because** an account with no trail can never deploy, and nothing here can fix that.

### Option 2: Always create a trail

- **Good, because** the alerts always have a trail.
- **Bad, because** an account already covered, or later covered by an organization trail, pays
  for every management event twice.

### Option 3: Create behind a switch, off by default, guarded

- **Good, because** an account with no trail gets one, and a covered account pays nothing more
  when the deploy follows the runner protocol.
- **Good, because** omitting the setting is the cheap case.
- **Bad, because** the repository owns account-wide audit infrastructure when the switch is on.
- **Bad, because** the duplicate-trail guard runs only in a pipeline that runs the proof scripts.

## Confirmation

1. `terraform/tests/trail.tftest.hcl` asserts the trail records what every alert needs, logs,
   is this account's own, and selects management events through one advanced selector; that the
   bucket is closed, refuses every caller not on TLS, and expires its logs; that the bucket
   policy's Allow statements admit only this trail; and that no trail is created when
   `manage_trail` is false.
2. `terraform/tests/portability.tftest.hcl` asserts omitted values fall to the safe defaults.
3. `tools/check_cloudtrail.sh --plan` runs before the apply and again, without `--plan`, after it,
   as the runner protocol requires; `tools/test_check_cloudtrail.sh` covers its selector
   decisions.

## Consequences

### Positive

- An account with no trail can deploy the alerts by setting one variable.
- An account already covered by a trail is never billed for a second when the deploy follows the
  runner protocol.

### Negative

- The repository owns account-wide audit infrastructure, a wider remit than "monitoring and
  alerts"; that is the reason the switch exists.
- The deploy role gains trail creation and bucket ownership, scoped to one trail name and one
  bucket.
- A year of logs is kept. Investigations reaching further back are not supported by this design.

### Neutral

- S3-managed encryption rather than KMS departs from CIS AWS Foundations control 3.7; see
  Compliance Notes.

## Assumptions

1. AWS keeps delivering one copy of management events free and billing every further copy.
2. The trail carries management events only; data events would reopen the encryption choice.
3. A year of retention meets the deploying organisation's investigation needs.

## Supersedes

None. This record revises part of ADR-0001's premise without replacing that record.

## Superseded by

None (current).

## Implementing PRs

- nwarila-platform/aws-monitoring-terraform-framework#1, "feat: email security group and IAM
  permission changes": the trail, its bucket, and the plan-aware trail checks.
- nwarila-platform/aws-monitoring-terraform-framework#3, "feat: deploy one commit to any account
  by changing providers.tf alone": `manage_trail` defaults to false.
- nwarila-platform/aws-monitoring-terraform-framework#13, "feat(alerts): email trail changes, and
  close the whole-project audit": logging, organization scope and the management-event selector
  stated on the trail, and the bucket's refusal of plain HTTP.

## Related ADRs

- [ADR-0001](0001-alert-from-eventbridge-not-log-metric-filters.md): this record revises its "do
  not manage the trail" premise. ADR-0001 remains in force for everything else.

## Compliance Notes

The trail uses S3-managed encryption rather than KMS, a departure from CIS AWS Foundations
control 3.7. The logs hold the same metadata the alerts already email in plain text, and a key
here would add cost and a grant without adding protection. Revisit if the trail ever carries
data events.

| Framework              | Control / Practice ID | Relationship                                                                    |
| ---------------------- | --------------------- | ------------------------------------------------------------------------------- |
| CIS AWS Foundations    | 3.7                   | Not met: S3-managed encryption, for the reason above.                            |
| NIST SP 800-53 Rev. 5  | AU-9, AU-11           | Log file validation, `prevent_destroy`, and a 365-day retention support protection and retention of audit records. |

## Changelog

| Date       | Change                                                     | Reason                                                   | Author/Role          | Body-diff? |
| ---------- | ---------------------------------------------------------- | -------------------------------------------------------- | -------------------- | ---------- |
| 2026-09-16 | Accepted.                                                  | ADR-0001's premise that a trail always exists did not hold. | Portfolio maintainer | Yes     |
| 2026-09-21 | `manage_trail` defaults to false instead of having no default (PR #3); prior text kept under Previous decisions. | Omitting the setting must never create a billable second trail. | Portfolio maintainer | Yes |
| 2026-09-22 | Restructured to the org ADR schema; replaced "supersedes" with "revises"; removed one deployment's inspection and pricing figure. | Bring the record to the required schema and keep it environment-neutral; supersession is for a whole different-subject record. | Portfolio maintainer | Yes |
| 2026-09-24 | Confirmation now names the three alerts, the explicit selector, and the bucket's TLS deny. | The trail's selector and transport rule became explicit, and a third alert reads the trail. | Portfolio maintainer | Yes |
| 2026-09-24 | Implementing PRs: added #13. | Record the pull request that carried this record's 2026-09-24 edits. | Portfolio maintainer | Yes |
