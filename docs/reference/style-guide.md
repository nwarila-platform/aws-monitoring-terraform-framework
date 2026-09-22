# Terraform coding and style guide

This repository writes the dialect of `aws-terraform-framework`, the org's reference framework.
Its full guide is the authority; this page lists the rules that bind here so a reader does not
need the larger repository open to review a change.

## File layout

Canonical filenames only, no numeric prefixes:

| File | Owns |
| --- | --- |
| `versions.tf` | `terraform { required_version, required_providers }` with exact `=` pins |
| `backend.tf` | the partial S3 backend; bucket identities never in-repo |
| `providers.tf` | the provider, its region, and its `default_tags`: the only file that chooses a region |
| `variables.tf` | every `variable` block |
| `data.tf` | every `data` block |
| `locals.tf` | every `locals` block: the "brain", where all shaping happens |
| `resources.tf` | every managed resource; consumes locals, never raw variables |
| `outputs.tf` | every `output` block |

Tests live in `terraform/tests/*.tftest.hcl`, named by subject.

## Variables

- No `optional()` type modifiers. Consumers express optionality with a value (`null`, `[]`,
  `{}`), never with a type constraint.
- `nullable = false` on every variable except those whose documented off switch is `null`.
- `description` is a `<<-EOT` heredoc: the first sentence says what the variable is; the rest
  say how it is used, what validates it, and what happens when it is empty.
- Every externally supplied string or number gets a `validation` block whose error message
  states the exact accepted form. A `bool` has no further form to check; its type is the whole
  contract.

## Resources

- Resources iterate maps via `for_each` with stable, human-readable keys; keys are part of the
  public contract.
- Every block opens with `provider = aws.us_east_1`; properties follow alphabetically. The alias
  keeps aws-terraform-framework's name for continuity; the region it targets is set in
  `providers.tf` and may be any region, including a GovCloud one.
- Resource blocks consume locals, not `var.*` directly; `locals.tf` is the only place shaping
  logic lives.
- Every taggable resource merges its `Name` under the six identity keys, which are also set as
  provider `default_tags` so they travel in the create request.
- Security invariants owned by the framework are hard-coded on the resource and asserted by
  test, never left to a variable.

## Comments

- `#` only; no `//` and no banner boxes.
- `#region ------ [ Title ] ---- #` and matching `#endregion` markers group `variables.tf`,
  `data.tf`, `locals.tf`, `resources.tf` and `outputs.tf`; titles name the AWS object family or
  the group's purpose. `.vscode/settings.json` folds on them.
- A comment states a constraint the code cannot show (why a value is forced, what breaks without
  it), never what the next line does.

## The 98-column rule

The budget binds comments and hand-written Markdown prose. Expression lines are formatted by
`terraform fmt` and are not rewrapped by hand. Generated files, mirrored ADRs, tables, fenced
code, and link URLs sit outside the rule.

## Validation and testing

- `terraform test` with `mock_provider` is the unit layer. Every alert pins its call list
  verbatim; every validation rule has an `expect_failures` run; computed wiring is asserted
  after a mocked `apply`.
- Mock values that must satisfy provider-side validation (ARNs) are set as `mock_resource` or
  `mock_data` defaults rather than left random.
- `make ci` is the single local gate and CI runs exactly it.

## Releases and history

- Squash-merge titles are Conventional Commits; breaking changes use `!` and a
  `BREAKING CHANGE:` footer.
