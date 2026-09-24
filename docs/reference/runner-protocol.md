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

A runner supplies `environment`, `alert_emails`, `alert_key_alias`, `manage_trail`, and
`exempt_pipeline_roles` from its own value file, copied into the framework checkout or passed with
`-var-file`. Start from `terraform/terraform.tfvars.example`.

## One Value File per Environment

Each environment is one account with its own value file and its own state. The framework commit is
the same for all of them; what differs is:

| Setting | Where it lives |
| --- | --- |
| `environment`, `alert_emails`, `alert_key_alias`, `manage_trail`, `exempt_pipeline_roles` | The environment's value file |
| Backend bucket, key, and region | The environment's backend configuration |
| Region and credentials | `terraform/providers.tf`, the only file that chooses a region |
| `repository`, `repository_id`, `commit_sha`, `run_id` | The pipeline, as command-line `-var` |

`alert_key_alias`, `manage_trail` and `exempt_pipeline_roles` have safe defaults: the framework
creates its own key, no trail is created, and nobody is exempt. `environment` and `alert_emails`
have none and must be set.

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
  alarms report a broken channel at runtime. A subscription lost afterwards, through a
  recipient's unsubscribe link or an SNS suspension, is caught only by a read-back that runs on
  a schedule: schedule one, or accept that its detection is unbounded.

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
2. obtain its deploy role's credentials and initialise the backend;
3. plan to a saved file with the four identity arguments;
4. run `tools/check_cloudtrail.sh --plan <plan>`, which refuses to create a second trail and
   refuses to proceed with no trail;
5. run `tools/check_event_patterns.sh <plan> [role ...]`, which tests every planned pattern
   against EventBridge with the fixtures under `tools/fixtures/events/`; a deployment that sets
   `exempt_pipeline_roles` names at least one real role the exemption covers, and each named role
   must prove exempt;
6. apply the saved plan;
7. run `tools/check_cloudtrail.sh` again, which now requires a covering trail outright; and
8. read back from AWS and fail on any mismatch: each rule, `ENABLED` on the default bus; each
   target, the alert topic with its dead-letter queue, retry policy and input transformer; both
   topics, the alert topic's key and policy and the health topic's absence of a key and its
   policy; the subscriptions, compared as the configured addresses rather than as counts; and
   each alarm's metric, dimensions, actions and enabled state.

A healthy converge of an unchanged framework commit updates identity tags only, `CommitSha` and
`RunId` on every resource, and never replaces a resource. A runner SHOULD state that expected
recap and treat any other change as a finding.

A deploy role whose deployment creates its own key needs `iam:GetRole` on its own ARN: the
framework asks IAM for the deploying role's real ARN, path included, to name it in the key policy
it writes, and a plan fails without that permission. A deployment that supplies a key by alias
writes no key policy, so it makes no such call. A pipeline that runs the proof scripts also needs
`events:TestEventPattern` and the CloudTrail read calls they make: `ListTrails`, `DescribeTrails`,
`GetTrailStatus`, and `GetEventSelectors`.

## Deploy Role Permissions

The deploy role needs the calls below: what the provider makes for these resources across create,
read, update, tag and delete, plus the reads a runner's own checks make. Every row except the last
is needed by a pipeline that runs only `init`, `plan`, and `apply`. Every taggable resource the
module creates carries the deployment's `RepositoryId` tag in the create request, so EventBridge,
CloudWatch, KMS, SQS and CloudTrail grants can be conditioned on `aws:RequestTag/RepositoryId` and
`aws:ResourceTag/RepositoryId`. S3 is the exception: it evaluates a bucket's tags only once
attribute-based access control is enabled on that bucket, which this module does not do, so the
trail bucket's grants name its ARN. Names are fixed, which lets every other grant name its
resource: `security-change-alerts` and the names that begin with it, the trail
`management-events`, and its bucket `<account-id>-cloudtrail`.

| Service | Calls | Scope |
| --- | --- | --- |
| EventBridge | `PutRule`, `DeleteRule`, `DescribeRule`, `PutTargets`, `RemoveTargets`, `ListTargetsByRule`, `TagResource`, `UntagResource`, `ListTagsForResource` | rules named `security-change-alerts-*` |
| SNS | `CreateTopic`, `DeleteTopic`, `GetTopicAttributes`, `SetTopicAttributes`, `Subscribe`, `Unsubscribe`, `GetSubscriptionAttributes`, `TagResource`, `UntagResource`, `ListTagsForResource`; `SetSubscriptionAttributes`, a drift repair the module never issues in normal operation; `ListSubscriptionsByTopic` for a read-back that lists them | the topics `security-change-alerts` and `security-change-alerts-health`; subscription calls are granted on the topic ARN |
| SQS | `CreateQueue`, `DeleteQueue`, `GetQueueAttributes`, `SetQueueAttributes`, `TagQueue`, `UntagQueue`, `ListQueueTags` | the queue `security-change-alerts-dlq` |
| KMS, only when the framework creates the key | `CreateKey`, `DescribeKey`, `GetKeyPolicy`, `PutKeyPolicy`, `GetKeyRotationStatus`, `EnableKeyRotation`, `UpdateKeyDescription`, `ListResourceTags`, `TagResource`, `UntagResource`, `ScheduleKeyDeletion`; `EnableKey`, a drift repair the module never issues in normal operation | `CreateKey` on `*` conditioned on the request tag; the rest on keys carrying the tag |
| KMS aliases, only when the framework creates the key | `CreateAlias`, `UpdateAlias`, `DeleteAlias` on the alias and the tagged key; `ListAliases` on `*` | `alias/security-change-alerts` |
| KMS, only when a key is supplied by alias | `DescribeKey` | the supplied key. Its policy must also authorize this role for that call, or the grant is inert, and must admit `events.amazonaws.com`; nothing else publishes through it |
| CloudWatch | `PutMetricAlarm`, `DeleteAlarms`, `DescribeAlarms`, `TagResource`, `UntagResource`, `ListTagsForResource` | alarms named `security-change-alerts-*`; the provider reads an alarm by name, so `DescribeAlarms` needs no wider scope |
| IAM, only when the framework creates the key | `GetRole` | the deploy role itself |
| S3, state | `GetObject`, `PutObject`, `DeleteObject`; `ListBucket` | the state object and its `.tflock`; the state prefix |
| CloudTrail, only with `manage_trail = true` | `CreateTrail`, `AddTags`, `RemoveTags`, `ListTags`, `UpdateTrail`, `DeleteTrail`, `StartLogging`, `StopLogging`, `PutEventSelectors`, `GetTrailStatus`, `GetEventSelectors` on the trail; `DescribeTrails`, which takes no resource | the trail `management-events`; `DescribeTrails` on `*` |
| S3, only with `manage_trail = true` | `CreateBucket`, `ListBucket`, `GetBucketAcl`, `GetBucketCORS`, `GetBucketWebsite`, `GetBucketVersioning`, `GetAccelerateConfiguration`, `GetBucketRequestPayment`, `GetBucketLogging`, `GetLifecycleConfiguration`, `GetReplicationConfiguration`, `GetEncryptionConfiguration`, `GetBucketObjectLockConfiguration`, `GetBucketTagging`, `GetBucketOwnershipControls`, `GetBucketPublicAccessBlock`, `GetBucketPolicy`, `PutBucketTagging`, `PutBucketOwnershipControls`, `PutBucketPublicAccessBlock`, `PutEncryptionConfiguration`, `PutLifecycleConfiguration`, `PutBucketPolicy`, `DeleteBucketPolicy`, `TagResource`, `UntagResource`, `ListTagsForResource` | the bucket `<account-id>-cloudtrail` |
| Proof scripts and any read-back | `events:TestEventPattern`; `cloudtrail:ListTrails`, `DescribeTrails`, `GetTrailStatus`, `GetEventSelectors` | `*` |

The S3 tagging calls appear because the provider tries `TagResource`, `UntagResource` and
`ListTagsForResource` first and falls back to the bucket-tagging calls only when they are denied;
granting them keeps the bucket's first apply on the direct path.

Four details decide whether a first apply succeeds:

- **Tag on create.** Where a grant is conditioned on the resource tag, the tagging call
  (`TagResource`, `TagQueue`, `AddTags`) must also be granted under the request-tag condition,
  because the tags arrive in the create request, before any resource tag exists.
- **The key policy names the deploy role**, when the framework writes one. KMS refuses to create
  a key whose policy would lock its creator out, so the module names the deploying role as an
  administrator of the key; that is why that role needs `iam:GetRole` on itself. A supplied key
  needs the opposite care: its policy is written by its owner, and must authorize this deploy
  role's `kms:DescribeKey`, or the IAM grant below is inert and the first plan fails at the
  lookup, and must admit `events.amazonaws.com`, or every alert deploys and never arrives. Those
  two are all it needs: the health topic carries no key.
- **Creating a trail reads it back.** Terraform finishes `CreateTrail` by reading the trail, which
  calls `DescribeTrails` and `GetTrailStatus` every time. A role that can create a trail but not
  read it leaves a created trail outside state and a failed apply.
- **Listing the state bucket.** Condition `s3:ListBucket` on the state prefix with
  `StringLikeIfExists`, not `StringLike`. Before the first apply the state object does not exist,
  and S3 decides between "not found" and "access denied" with a `ListBucket` check that carries no
  prefix. Under `StringLike` that check is denied, S3 answers access denied, and Terraform, which
  treats only "not found" as empty state, fails.
