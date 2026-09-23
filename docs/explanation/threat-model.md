# Threat Model

This threat model covers the Terraform root module in this repository: the code path from
tracked source, through local or CI validation, to the workload AWS account it deploys into.

## Scope

What this module guarantees:

- Terraform and the AWS provider are exact-pinned in `terraform/versions.tf`, with provider
  checksums recorded in `terraform/.terraform.lock.hcl`.
- The alert topic is encrypted at rest with a customer managed key. Where this module owns that
  key it rotates it yearly; where a deployment names an existing key by alias, rotation and the
  key policy belong to that key's owner, and Terraform cannot read a key policy to check it. The
  key policy admits EventBridge with the two actions the SNS developer guide names and keeps the
  account root as administrator.
- The topic policy admits `sns:Publish` from `events.amazonaws.com` and nothing else.
- Every rule matches write calls only, on an exact `eventName` list asserted by test.
- Local and CI validation run without live AWS credentials by using Terraform's mock-provider
  test support.

## Trust Boundaries

- **Repository to CI.** CI checks out this repository and runs `make ci` with pinned tooling;
  `.github/workflows/ci.yaml` grants it read access to the repository and no cloud credentials.
- **Terraform to AWS provider registry.** `terraform init` downloads `hashicorp/aws` and
  verifies the selected artifact against the committed lock file.
- **Runner to the workload account.** The deploy role's credentials belong to one pipeline, and
  binding that trust to the pipeline and its protected branch is the runner's responsibility; this
  module cannot see how the pipeline authenticates. Scoping the role's permissions to the
  resources this module creates is the runner's responsibility too.
- **CloudTrail to EventBridge.** The trail is created by this framework when `manage_trail` is
  set, and is otherwise owned outside it. Either way the runner proves one is logging write
  management events, because a rule with no trail behind it is silent and green.
- **SNS to recipients.** Delivery is email. A recipient's inbox is outside every control here.

## Accepted residuals

- **Alert content is metadata, not secrets.** The email quotes CloudTrail's `requestParameters`
  for the call. For the calls alerted on, that is group ids, rule definitions, role names and
  policy documents, all of which the recipient can read in the console anyway.
- **The topic policy carries no source condition.** The EventBridge user guide's statement for
  SNS targets is reproduced as written, without one. Any EventBridge rule in this account may
  therefore choose this topic as a target and email the recipients. Creating such a rule needs
  `events:PutTargets` in this account, which is already the ability to do worse.
- **The key policy carries no source condition.** The SNS developer guide states that
  `aws:SourceArn` and `aws:SourceAccount` are unsupported for EventBridge publishing to an
  encrypted topic, so the key admits the service principal outright.
- **Named automation roles may be exempt from the security-group alert.** Automation that rewrites
  security groups on every run produces far more events than a person can read, which buries the
  changes a person needs to see. The roles in `exempt_pipeline_roles`, named exactly or matched by
  a `*` pattern, therefore do not raise security-group alerts. Their IAM changes still alert, a
  change made through an IAM Identity Center sign-in role still alerts because no entry may reach
  those roles, and an event with no assumed-role identity still alerts. A pattern also exempts
  roles created later under the same name, which is the point: an exact list silently falls behind
  a growing fleet of pipelines. Creating such a role still raises the IAM alert. The residual is a
  stolen credential for an exempt role used to change a security group, which is visible in
  CloudTrail but not emailed. The default exempts nobody.
- **Only one region is watched.** Security-group events are recorded in the region of the call,
  so a group created outside the supported region raises no alert. This is only safe alongside an
  account control that prevents use of other regions; without that control it is an open gap
  rather than a residual. IAM is unaffected, because its events are global and land in the
  supported region.
- **A pending subscription delivers nothing.** SNS emails a confirmation link; only the
  recipient can follow it, and the deploy summary lists who has not. Each recipient now confirms
  twice, once for alerts and once for channel health.
- **The health channel is not itself watched.** If the health topic breaks, nothing reports it.
  Watching the watcher has to stop somewhere, and this is where.
- **Read calls are invisible.** `ENABLED` rules match write management events only. Reading a
  role's policy is not a change and is not alerted.
