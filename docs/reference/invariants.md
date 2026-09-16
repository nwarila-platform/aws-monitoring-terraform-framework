# Invariants

Non-negotiable rules for this module. Violating one of these is a breaking change at minimum.

- Terraform Core and provider versions MUST remain exact-pinned.
- `terraform/.terraform.lock.hcl` MUST be committed with checksums for the supported
  contributor and CI platforms.
- The supported region MUST remain exactly `us_east_1`; adding a region is a code change, not a
  value change. IAM calls are recorded there as global service events, so the region is also
  where the IAM alert has to live.
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
- The topic MUST be encrypted with a key this module owns, with yearly rotation enabled, and the
  key policy MUST carry the SNS developer guide's statement for event sources verbatim: the two
  actions to `events.amazonaws.com` with no source condition.
- The topic policy MUST admit `sns:Publish` from `events.amazonaws.com` and no other principal.
- Recipients MUST be email subscriptions created pending; nothing in this module MAY confirm one.
- Deployment identity MUST arrive as command-line `-var` arguments and MUST be stamped on every
  taggable resource; the committed `terraform.tfvars` MUST NOT set it.
- The deploy MUST prove a logging trail covers the region before applying, and MUST read the
  rules, target, key and subscriptions back from AWS after applying. Proving the trail MUST
  reject a trail that records only read events and one that filters out either alerted service.
- A `prod` deployment MUST name at least one recipient, and the deploy MUST fail when the live
  subscription count is short of the configured one.
- Resource keys used in outputs (`iam-role`, `security-group`, recipient addresses) MUST remain
  stable across patch versions.
