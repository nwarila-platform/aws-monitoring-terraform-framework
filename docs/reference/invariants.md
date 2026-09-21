# Invariants

Non-negotiable rules for this module. Violating one of these is a breaking change at minimum.

- Terraform Core and provider versions MUST remain exact-pinned.
- `terraform/.terraform.lock.hcl` MUST be committed with checksums for the supported
  contributor and CI platforms.
- `terraform/providers.tf` MUST be the only file that names a region, and no expression may write
  an ARN partition literally. Every ARN the framework writes itself MUST take its partition from
  `data.aws_partition` and any region from `data.aws_region`, so one commit deploys to commercial
  and GovCloud accounts by swapping that file alone. `tests/portability.tftest.hcl` enforces it.
- Every alert MUST be an exact `eventName` list of write calls, asserted verbatim by test. A
  pattern that matches by prefix, or that matches read calls, is not an alert this module ships.
- A principal exemption MUST apply to the security-group alert only, MUST never apply to IAM, and
  MUST keep matching events that carry no assumed-role identity. Excluding a nested field alone
  drops every event lacking that field, which would silently lose root-user and service-made
  changes along with the pipelines.
- Every rule's pattern MUST be proven against EventBridge with fixtures before an apply; a new
  alert MUST ship with its own fixtures under `tools/fixtures/events/<key>/`.
- The target input template MUST be valid JSON, and the whole event MUST travel as a JSON value.
  Only paths present on every API-call event may be quoted individually.
- The supported region is the estate's only region by control, not by convention. The account
  MUST deny or otherwise prevent resource creation in regions this framework does not watch;
  without that control, a security group created elsewhere produces no alert.
- Every rule MUST be `ENABLED` on the `default` event bus: CloudTrail delivers there only, and
  the default state is what matches write management events.
- The key policy MUST name the deploying role for key administration, so that KMS's lockout safety
  check on `CreateKey` never depends on a tag the key cannot yet carry. The role MUST be named as
  IAM reports it through `aws_iam_session_context`, never rebuilt from the session ARN, which drops
  the role's path.
- The topic MUST be encrypted with a key this module owns, with yearly rotation enabled, and the
  key policy MUST carry the SNS developer guide's statement for event sources verbatim: the two
  actions to `events.amazonaws.com` with no source condition.
- The topic policy MUST admit `sns:Publish` from `events.amazonaws.com` and no other principal.
- Recipients MUST be email subscriptions created pending; nothing in this module MAY confirm one.
- Every target MUST have a dead-letter queue, and that queue MUST accept messages only from this
  framework's own rules, named individually rather than by wildcard.
- The alert channel MUST report its own failures, and MUST do so through a topic other than the
  one carrying the alerts. Alarms MUST treat missing data as healthy, because the metrics they
  watch are published only when non-zero.
- Deployment identity MUST arrive as command-line `-var` arguments and MUST be stamped on every
  taggable resource; the committed `terraform.tfvars` MUST NOT set it.
- The framework MUST NOT create a trail in an account already covered by one; the deploy MUST
  decide that from the saved plan and fail rather than add a billable second copy.
- A trail this framework owns MUST be multi-region, MUST include global service events, MUST
  validate its log files, and MUST carry `prevent_destroy` along with its bucket.
- A runner MUST prove a logging trail covers the region before applying, and MUST read the
  rules, target, key and subscriptions back from AWS after applying. Proving the trail MUST
  reject a trail that records only read events and one that filters out either alerted service.
- A `prod` deployment MUST name at least one recipient, and the deploy MUST fail when the live
  subscription count is short of the configured one.
- Resource keys used in outputs (`iam`, `security-group`, recipient addresses) MUST remain
  stable across patch versions.
