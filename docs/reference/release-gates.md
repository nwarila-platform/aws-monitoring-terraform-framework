# Release Gates

PRs to `main` must pass:

- `CI` (`make ci`: Terraform fmt/init/validate/test, TFLint, terraform-docs diff, Diataxis docs
  layout, and the bidirectional deny-all `.gitignore` allowlist guard)
- `Security` (the local `security.yaml` caller, which delegates to the namespace-local
  `nwarila-platform/.github` CodeQL, IaC/security, and Scorecard reusables per org ADR-0005)
- `Template Sync` (`NWarila/drift-gate` against `NWarila/terraform-framework-template` current
  `main` pin `ba73041b808ceae584f482e6bec2970c1bdc019b`). This repository has never been
  reconciled against that baseline; its first run is expected to report the files this
  repository deliberately shapes differently, and reconciling the pin is tracked as follow-up.
- `Repo Hygiene` (`nwarila-platform/.github` repo-hygiene policy)

Merging to `main` runs `AWS Deploy`, which is not a gate but the deployment itself: it proves the
trail, plans, applies, and verifies against AWS. A red deploy is a live incident, not a failed
check.

Workflow and action references are 40-character SHA-pinned per the repo-hygiene contract.
