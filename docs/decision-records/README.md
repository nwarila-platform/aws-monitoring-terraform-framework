# Architecture Decision Records

This directory holds the Architecture Decision Records (ADRs) governing this repository, split
into three scopes per [ADR-0001](org/0001-use-architecture-decision-records.md):

- [`org/`](org/) - byte-identical mirrors of the org-baseline ADRs whose master copies live in
  [`nwarila-platform/.github`](https://github.com/nwarila-platform/.github/tree/main/docs/decision-records).
- [`template/`](template/) - byte-identical mirrors of Terraform framework template ADRs
  inherited from `NWarila/terraform-framework-template`.
- [`repo/`](repo/) - repository-specific ADRs that apply only to this repo.

## Index

### Org-Mirrored

| # | Title | Status | Date | Summary |
| --- | --- | --- | --- | --- |
| [org/0001](org/0001-use-architecture-decision-records.md) | Use Architecture Decision Records to Document Design Rationale | Accepted | 2026-04-22 | Adopt ADRs as the documentation format for architecturally significant decisions. |
| [org/0002](org/0002-adopt-diataxis-documentation-framework.md) | Adopt Diataxis as the Documentation Framework | Accepted | 2026-04-24 | Adopt the Diataxis four-quadrant framework for non-ADR documentation in adopting repositories. |
| [org/0003](org/0003-use-deny-all-gitignore-strategy.md) | Use a Deny-All `.gitignore` Strategy | Accepted | 2026-04-25 | Adopt deny-all `.gitignore` with explicit allowlist as the default tracking strategy for adopting repositories. |
| [org/0004](org/0004-use-renovate-for-dependency-updates.md) | Use Renovate for Dependency Updates with Per-Template Baselines | Accepted | 2026-06-02 | Adopt Renovate org-wide; each type-template owns a self-contained Renovate baseline. |
| [org/0005](org/0005-keep-github-control-planes-namespace-local.md) | Keep GitHub Control Planes Namespace-Local | Accepted | 2026-06-01 | Keep org governance, ADRs, repo hygiene, and reusable workflow callers in the owning namespace control plane. |

### Template-Mirrored

| # | Title | Status | Date | Summary |
| --- | --- | --- | --- | --- |
| [template/0001](template/0001-pin-terraform-and-provider-versions-exactly.md) | Pin Terraform and Provider Versions Exactly | Accepted | 2026-05-06 | Pin the Terraform CLI and every provider to exact versions. |
| [template/0002](template/0002-keep-reference-framework-credential-free.md) | Keep Reference Framework Credential-Free | Accepted | 2026-05-07 | Keep the reference framework credential-free, cost-free, and synthetic. |
| [template/0004](template/0004-isolate-pull-request-target-triggers.md) | Isolate Pull Request Target Triggers | Accepted | 2026-05-10 | Keep `pull_request_target` isolated to trusted-bot auto-merge. |
| [template/0005](template/0005-classify-org-control-plane-callers-as-scaffold.md) | Classify Org Control Plane Callers as Scaffold | Accepted | 2026-05-30 | Keep namespace-specific org-control-plane callers out of byte-identity enforcement. |

### Repository-Specific

| # | Title | Status | Date | Summary |
| --- | --- | --- | --- | --- |
| [repo/0001](repo/0001-alert-from-eventbridge-not-log-metric-filters.md) | Alert From EventBridge, Not Log Metric Filters | Accepted | 2026-09-15 | Match CloudTrail events in EventBridge and publish to an encrypted SNS topic; the deploy proves a logging trail covers the region, and repo/0003 decides whether the framework creates it. |
| [repo/0002](repo/0002-alert-on-what-a-person-will-act-on.md) | Alert on What a Person Will Act On | Accepted | 2026-09-16 | Cover the calls that change authorisation, exempt deploy pipelines from the security-group alert only, send JSON, and prove every pattern against EventBridge. |
| [repo/0003](repo/0003-own-the-trail-behind-a-switch.md) | Own the Trail, Behind a Switch | Accepted | 2026-09-16 | Create the multi-region trail the alerts depend on when `manage_trail` is set, and never create a second one in an account that already has coverage. |

## Authoring Rules

- Org-baseline ADRs are mirrors only. Do not edit files under `org/` in this repository
  directly; update the master copy in `nwarila-platform/.github` and sync it down.
- Repo-specific ADRs go under `repo/`. The `repo/` namespace is independent of `org/`, so
  `org/0001` and `repo/0001` can coexist.
- Updating this index belongs in the same PR as adding a new ADR.
