# Terraform Runner Protocol

This repository supplies a Terraform root module under `terraform/` and the scripts that prove a
deployment is safe to apply. It does not deploy anything itself. A runner repository integrates
with it the way `aws-monitoring-terraform-runner` does, and owns checkout, authentication,
deployment values, approval gates, and evidence.

## Framework Checkout

A runner checks out this repository at a reviewed, immutable commit recorded in its own
repository, for example `.github/terraform-framework-pin`. Updating that pin is a runner change
and goes through the runner's normal review. The checked-out commit is the framework version
Terraform evaluates, and the version of the proof scripts the runner runs.

## Backend Configuration

The module declares a partial S3 backend in `terraform/backend.tf`. The runner supplies bucket,
key, and region. Backend encryption and S3-native locking are invariants declared in
`terraform/backend.tf`. Start from `terraform/backend.hcl.example` for a workstation plan.

## Terraform Inputs

A runner supplies `environment`, `alert_emails`, `manage_trail`, and `exempt_pipeline_roles` from
its own value file, copied into the framework checkout or passed with `-var-file`. Start from
`terraform/terraform.tfvars.example`.

## Deployment Identity

Every plan requires these four command-line variables. All are mandatory and non-nullable; there
is no unattributed deployment:

- `repository`: the runner repository as an `owner/name` slug.
- `repository_id`: the numeric, rename-stable GitHub repository id.
- `commit_sha`: the lowercase SHA of the checked-out runner commit.
- `run_id`: the numeric GitHub Actions run id, or another numeric run identifier for local use.

Pass them as command-line `-var` arguments so they outrank every value file. The module writes
them into the tag map of every taggable resource and also sets the six uniform keys as provider
`default_tags`, so they travel in the create request where a deploy role's tag conditions see them.

## Runner Responsibilities

A runner MUST, in this order:

1. check out a reviewed framework commit and its own values;
2. assume its deploy role over OIDC and initialise the backend;
3. plan to a saved file with the four identity arguments;
4. run `tools/check_cloudtrail.sh --plan <plan>`, which refuses to create a second trail and
   refuses to proceed with no trail;
5. run `tools/check_event_patterns.sh <plan>`, which tests every planned pattern against
   EventBridge with the fixtures under `tools/fixtures/events/`;
6. apply the saved plan;
7. run `tools/check_cloudtrail.sh` again, which now requires a covering trail outright; and
8. read the rules, targets, topics, subscriptions, and alarms back from AWS and fail on any
   mismatch.

The deploy role needs, beyond the resources it manages, `events:TestEventPattern` and the
CloudTrail read calls these scripts make: `ListTrails`, `DescribeTrails`, `GetTrailStatus`, and
`GetEventSelectors`.
