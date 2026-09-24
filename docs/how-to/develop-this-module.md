# Develop this module

## Local setup

Install the same pinned tools that the `CI` workflow installs before running `make ci`:

- Terraform 1.15.1
- actionlint 1.7.12
- markdownlint-cli2 0.22.1
- TFLint 0.62.0
- terraform-docs 0.23.0
- Python 3 (standard library only, for `tools/check_docs_layout.py`)

`tools/install_ci_tools.sh` installs all but Terraform into `~/.local/bin` when the four
`*_VERSION` variables are set as `.github/workflows/ci.yaml` sets them.

## The development loop

```sh
make fmt        # format Terraform
make ci         # run every gate
make docs       # regenerate docs/reference/terraform.md
```

## Adding an alert

1. Add an entry to `local.change_alerts` in `terraform/locals.tf`: the CloudTrail `source`,
   `eventSource`, the exact write calls, a headline, a description, and whether pipelines are
   exempt. The rule, target and alarm names are derived from the entry's key.
2. Add its fixtures under `tools/fixtures/events/<key>/`, at least one `match-*.json` and one
   `nomatch-*.json`, and allowlist the directory and its files in `.gitignore`; the deploy proves
   every rule against them and refuses a rule that has none.
3. Add a run to `terraform/tests/alerts.tftest.hcl` that pins the new rule's event pattern
   verbatim, and move the runs that count rules and alarms.
4. Run `make ci`, then `make docs`.

## Before opening a PR

```sh
make ci
```

If `make ci` is green locally, the `CI` workflow should be green in GitHub Actions.

## Merge titles are the release pipeline

Releases are cut by release-please, which classifies **squash-merge commit titles** on `main`. A
title that does not follow Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`,
`refactor:`, `test:`, with `!` or a `BREAKING CHANGE:` footer for breaking changes) is
invisible to the release pipeline: it lands on `main` but can never be released or listed in
the CHANGELOG.

Rules:

- The PR title (which becomes the squash commit title) MUST be a Conventional Commit. Review it
  like code.
- Automation prefixes such as `[bot]` never belong in the title; put them in the PR body.
- Merging to `main` deploys nothing. A runner adopts the merge by updating its framework pin.
