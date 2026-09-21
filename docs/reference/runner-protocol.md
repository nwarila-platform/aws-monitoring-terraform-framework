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

## One Value File per Environment

Each environment is one account with its own value file and its own state. The framework commit is
the same for all of them; what differs is:

| Setting | Where it lives |
| --- | --- |
| `environment`, `alert_emails`, `manage_trail`, `exempt_pipeline_roles` | The environment's value file |
| Backend bucket, key, and region | The environment's backend configuration |
| Region and credentials | `terraform/providers.tf`, the only file that chooses a region |
| `repository`, `repository_id`, `commit_sha`, `run_id` | The pipeline, as command-line `-var` |

`manage_trail` and `exempt_pipeline_roles` have safe defaults: no trail is created and nobody is
exempt. `environment` and `alert_emails` have none and must be set.

## Terraform-Only Pipelines

A pipeline that runs only `init`, `plan`, and `apply` skips the proof scripts in `tools/`, and
the provider offers no data source that can read CloudTrail trails, so their checks cannot move
into Terraform. What such a pipeline gives up, and what covers it:

- **The event-pattern proof.** The patterns are framework code, identical in every environment;
  a pipeline that runs `tools/check_event_patterns.sh` on every framework change proves them
  before any terraform-only environment adopts that commit.
- **The duplicate-trail guard.** Covered by the default: `manage_trail = false` never creates a
  trail. Set it true only after confirming the account has none.
- **The missing-trail guard.** Not covered by Terraform. Before the first apply in each account,
  confirm a trail is logging write management events, including global service events:

  ```sh
  AWS_REGION=<region> tools/check_cloudtrail.sh
  ```

- **The post-apply read-back.** A failed create already fails `apply`, and the delivery-failure
  alarms report a broken channel at runtime.

## Deployment Identity

Every plan requires these four command-line variables. All are mandatory and non-nullable; there
is no unattributed deployment:

- `repository`: the deploying repository's path, such as `owner/name` or `group/subgroup/name`.
- `repository_id`: the numeric, rename-stable id the source host gives the repository or project.
- `commit_sha`: the lowercase SHA of the checked-out runner commit.
- `run_id`: the numeric id of the pipeline run or build, or another numeric identifier for local
  use.

Pass them as command-line `-var` arguments so they outrank every value file. The module writes
them into the tag map of every taggable resource and also sets the six uniform keys as provider
`default_tags`, so they travel in the create request where a deploy role's tag conditions see
them.

## Runner Responsibilities

A runner MUST, in this order:

1. check out a reviewed framework commit and its own values;
2. assume its deploy role over OIDC and initialise the backend;
3. plan to a saved file with the four identity arguments;
4. run `tools/check_cloudtrail.sh --plan <plan>`, which refuses to create a second trail and
   refuses to proceed with no trail;
5. run `tools/check_event_patterns.sh <plan> [role ...]`, which tests every planned pattern
   against EventBridge with the fixtures under `tools/fixtures/events/`; a deployment that sets
   `exempt_pipeline_roles` names at least one real role the exemption covers, and each named role
   must prove exempt;
6. apply the saved plan;
7. run `tools/check_cloudtrail.sh` again, which now requires a covering trail outright; and
8. read the rules, targets, topics, subscriptions, and alarms back from AWS and fail on any
   mismatch.

Every deploy role, in every environment, needs `iam:GetRole` on its own ARN: the framework asks
IAM for the deploying role's real ARN, path included, to name it in the KMS key policy, and a plan
fails without that permission. A pipeline that runs the proof scripts also needs
`events:TestEventPattern` and the CloudTrail read calls they make: `ListTrails`, `DescribeTrails`,
`GetTrailStatus`, and `GetEventSelectors`.
