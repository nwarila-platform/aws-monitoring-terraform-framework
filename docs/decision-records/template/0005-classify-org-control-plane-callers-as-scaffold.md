# ADR-template/0005: Classify Org Control Plane Callers as Scaffold

| Field          | Value                                   |
| -------------- | --------------------------------------- |
| Status         | Accepted                                |
| Date           | 2026-06-01                              |
| Authors        | Nick Warila (@NWarila)                  |
| Decision-maker | Nick Warila (sole portfolio maintainer) |
| Consulted      | Drift-gate findings from `nwarila-platform/proxmox-terraform-framework`. |
| Informed       | Maintainers of derivative Terraform framework repositories. |
| Reversibility  | Medium                                  |
| Review-by      | 2026-11-29                              |

## TL;DR

`terraform-framework-template` keeps only namespace-agnostic framework files in `baseline-manifest.json` `byte_identical`. Files that embed an org `.github` control-plane repository, such as `.github/workflows/security.yaml` and `docs/reference/mirroring.md`, are scaffold starter files. Derivative frameworks keep the template's shape but repoint those files to their owning namespace's `.github` repository.

## Context and Problem Statement

Derivative Terraform frameworks may live outside the `NWarila` namespace while still deriving from `NWarila/terraform-framework-template`. `nwarila-platform/proxmox-terraform-framework` is one such consumer. It should use `nwarila-platform/.github` for repo hygiene, CodeQL, security scanning, Scorecard, and org baseline references, even though the Terraform framework template itself lives under `NWarila`.

The previous manifest classification treated `.github/workflows/security.yaml` and `docs/reference/mirroring.md` as byte-identical. Drift-gate therefore failed when Proxmox correctly repointed those files to `nwarila-platform/.github`. The failure was useful evidence: drift-gate was enforcing the manifest as written, but the manifest no longer described the intended ownership boundary.

The template needs to distinguish files that are framework-contractual from files that are starter material with namespace-specific values.

## Decision Drivers

1. **Correct trust boundary.** Derivative frameworks should call the `.github` control plane owned by their repository namespace.
2. **Meaningful drift gates.** Drift-gate should fail on accidental drift, not on intentional namespace-local values.
3. **Template reuse.** `NWarila/terraform-framework-template` should remain useful to framework repos outside `NWarila`.
4. **Small byte-identical surface.** Only files whose exact bytes are truly contractual should be byte-enforced.
5. **Readable manifest.** The manifest should communicate propagation semantics directly.

## Considered Options

1. Keep `.github/workflows/security.yaml` and `docs/reference/mirroring.md` byte-identical.
2. Remove drift-gate for derivative framework repositories.
3. Classify org-control-plane caller files as scaffold starter files and keep namespace-agnostic files byte-identical.

## Decision Outcome

Chosen option: **Option 3, classify org-control-plane caller files as scaffold starter files.**

`baseline-manifest.json` keeps `docs/reference/runner-protocol.md` in `scaffold_starter` because derivative frameworks customize runner overlay paths, runtime fixture inventories, and evidence-artifact descriptions to match the framework they actually support.

Files that mention an org `.github` repository move to `scaffold_starter`. That includes:

- `.github/workflows/security.yaml`, because derivative frameworks must call the owning namespace's reusable CodeQL, IaC/security, and Scorecard workflows.
- `docs/reference/mirroring.md`, because derivative frameworks must name the owning namespace's org baseline repository.

Derivative framework repositories still receive these files as starter material and should keep their structure aligned with the template unless a repo-specific decision says otherwise. They are not byte-compared by drift-gate because their control-plane repository names are expected to vary.

## Pros and Cons of the Options

### Option 1: Keep org-control-plane callers byte-identical

- **Good, because** the manifest remains stricter.
- **Bad, because** it forces platform repositories to call `NWarila/.github`.
- **Bad, because** it turns a correct namespace-local edit into a drift-gate failure.
- **Bad, because** it contradicts the org-control-plane ownership model.

### Option 2: Remove drift-gate

- **Good, because** namespace-specific edits stop failing.
- **Bad, because** derivative frameworks lose useful protection for files that should remain identical.
- **Bad, because** it weakens a working control instead of correcting the manifest.

### Option 3: Make org-control-plane callers scaffold starter files

- **Good, because** drift-gate still enforces the files that are truly byte-identical.
- **Good, because** platform consumers can use platform-owned `.github` workflows.
- **Good, because** the manifest documents which files are starter material.
- **Neutral, because** reviewers must inspect scaffold changes instead of relying on byte comparison.

## Confirmation

Adherence to this ADR is confirmed by the following mechanisms. The wording `MUST`, `SHOULD`, and `MAY` follows RFC 2119 conventions.

1. **Manifest classification.** `baseline-manifest.json` MUST NOT place files that embed org `.github` repository names in `byte_identical` unless every intended consumer shares that same namespace.
2. **Runner protocol check.** Namespace-agnostic framework contracts, such as `docs/reference/runner-protocol.md`, MAY remain byte-identical.
3. **Consumer workflow check.** A derivative framework's workflow callers MUST use the `.github` repository owned by the derivative framework's namespace for org governance workflows.
4. **Drift-gate check.** A drift-gate failure on a scaffold file indicates a manifest classification bug, not necessarily a consumer defect.
5. **Review rule.** PRs that move a file from `scaffold_starter` to `byte_identical` MUST explain why every expected consumer can share the exact bytes.

## Consequences

### Positive

- Drift-gate keeps enforcing the core framework contract without blocking namespace-local control-plane ownership.
- Derivative frameworks can safely live in `nwarila-platform` while deriving from a `NWarila` type-template.
- The manifest communicates which files are exact contracts and which files are starter material.

### Negative

- Security caller and mirroring documentation changes require human review in each derivative framework.
- Template authors must maintain the distinction between shape compatibility and byte identity.

### Neutral

- This ADR does not change the reusable workflow implementation in this template.
- This ADR does not remove drift-gate; it narrows what drift-gate enforces byte-for-byte.

## Assumptions

1. Derivative frameworks may exist in namespaces other than `NWarila`.
2. Each namespace maintains an appropriate `.github` control plane for its repositories.
3. Drift-gate continues to support a `scaffold_starter` classification that is validated for shape but not byte-compared.

## Supersedes

None.

## Superseded by

None (current).

## Implementing PRs

Pending. This ADR is implemented by the PR that adds it, demotes the org-control-plane caller files in `baseline-manifest.json`, and bumps affected consumers to the new template source ref.

## Related ADRs

- [Org ADR-0006](../org/0006-keep-github-control-planes-namespace-local.md) records the namespace-local `.github` control-plane rule.
- [ADR-template/0004](0004-isolate-pull-request-target-triggers.md) records the privileged workflow trigger boundary that workflow callers must preserve.

## Compliance Notes

This ADR supports configuration management by making the drift-gate contract match the intended ownership boundary. It does not itself prove compliance.
