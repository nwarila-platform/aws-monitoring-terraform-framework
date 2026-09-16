# ADR-0003: Own the Trail, Behind a Switch

| Field            | Value                                                                       |
| ---------------- | --------------------------------------------------------------------------- |
| ID               | ADR-0003                                                                    |
| Scope            | Repository-specific                                                         |
| Status           | Accepted                                                                    |
| Decision-subject | Whether this framework creates the CloudTrail trail its alerts depend on.   |
| Date accepted    | 2026-09-16                                                                  |
| Date             | 2026-09-16                                                                  |
| Last reviewed    | 2026-09-16                                                                  |
| Authors          | Nick Warila (@NWarila)                                                      |
| Decision-makers  | Nick Warila (sole portfolio maintainer)                                     |
| Consulted        | Independent audits; live inspection of both accounts.                       |
| Informed         | Framework maintainers.                                                      |
| Reversibility    | Medium                                                                      |
| Review-by        | 2027-03-16                                                                  |

## TL;DR

The framework creates a multi-region trail with log file validation, writing to its own closed
bucket with a one-year expiry, when `manage_trail` is set. It is off unless a deployment asks
for it, because a second trail in an account bills every management event twice. This supersedes
the part of [ADR-0001](0001-alert-from-eventbridge-not-log-metric-filters.md) that treated the
trail purely as a prerequisite.

## Context and Problem Statement

ADR-0001 decided not to manage the trail, on the premise that the account would already have
one. Inspection of both accounts on 2026-09-15 found no trail at all, organization trails
included. The premise was wrong, so the alerts depended on something nobody owned, and the
deploy's only possible behaviour was to fail politely forever.

Creating one unconditionally is also wrong. AWS delivers one copy of an account's management
events to S3 free and bills $2.00 per 100,000 events for every copy after that. An organization
trail places a copy of itself in each member account, so an account that gains one later would
be paying twice for the same records if this framework had created its own.

## Decision

- A `manage_trail` variable, set per deployment, decides whether the trail is created. It has no
  default: a deployment states which case it is in.
- When set, the framework creates a multi-region trail including global service events, with log
  file validation on, writing to a bucket it owns with public access blocked, ACLs disabled,
  S3-managed encryption, and a 365-day expiry.
- The trail and its bucket carry `prevent_destroy`. Losing them removes the account's audit
  record, which is worse than any alert this framework raises.
- The deploy decides from the saved plan which check to run. If the plan creates a trail, no
  other covering trail may already exist. If it does not, a covering trail must already exist.
  After the apply, a covering trail must exist either way.

## Consequences

- The repository now owns account-wide audit infrastructure, which is a wider remit than
  "monitoring and alerts" and is the reason the switch exists.
- The deploy role gains trail creation and bucket ownership. That widening is one-time and
  scoped to one trail name and one bucket.
- S3-managed encryption rather than KMS departs from CIS AWS Foundations control 3.7. The logs
  hold the same metadata the alerts already email in plain text, and a key here would add cost
  and a grant without adding protection. Revisit if the trail ever carries data events.
- A year of logs is kept. Investigations reaching further back are not supported by this design.
