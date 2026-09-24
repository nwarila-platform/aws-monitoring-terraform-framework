# Release Gates

PRs to `main` must pass:

- `CI` (`make ci`: Terraform fmt/init/validate/test, the offline trail-gate proof
  (`trail-check`), the region-and-partition tripwire (`portability-check`), TFLint,
  terraform-docs diff, Diataxis docs layout, and the bidirectional deny-all `.gitignore`
  allowlist guard)
- `Security` (the local `security.yaml` caller, which delegates to the namespace-local
  `nwarila-platform/.github` CodeQL, IaC/security, and Scorecard reusables per org ADR-0005)
- `Workflow containers` (`template-drift / run / check` for the pinned org and
  `NWarila/terraform-framework-template` policies in `.github/.config/template-drift.lock`)
- `Repo Hygiene` (`nwarila-platform/.github` repo-hygiene policy)

Merging to `main` deploys nothing. A runner adopts a merged commit by updating its framework pin.

Workflow and action references are 40-character SHA-pinned per the repo-hygiene contract.
