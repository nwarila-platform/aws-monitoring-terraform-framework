# Testing Strategy

## What The Tests Cover

`terraform test` runs with a mocked AWS provider, so the tests exercise Terraform configuration
behavior without making AWS API calls.

- `terraform/tests/alerts.tftest.hcl` pins each of the three rules' event patterns to its exact
  list of write calls, pins both branches of the pipeline exemption and proves the IAM and
  CloudTrail alerts carry none, asserts the rules are `ENABLED` on the default bus, that every
  rule targets the one topic through the transformer, that each template is valid JSON once its
  placeholders are substituted, that the key states every value the design depends on, that the
  key policy admits EventBridge without a condition, keeps the account root, and names the deploy
  role with exactly the calls this configuration makes, that the topic policy admits EventBridge
  only, that each address is one email subscription, that no addresses means no subscriptions and
  nothing else changes, and that the outputs record it all.
- The supplied-key runs in `alerts.tftest.hcl` name a key by alias and assert that no key, no
  alias and no session-context lookup are planned, that the alert topic carries the resolved
  key's own id rather than the alias and the health topic no key at all, and that the output
  reports the key as not the framework's. Two runs drive the lookup's postconditions, each
  overriding the whole mocked key with exactly one thing wrong: an asymmetric key and one pending
  deletion.
- The reliability runs in `alerts.tftest.hcl` assert the dead-letter queue is wired to every
  target with a one-hour retry window, that its policy names only this framework's rules, that
  every alarm is enabled, reports to the health topic on both transitions, watches its own rule,
  the queue or the alert topic by name, and treats missing data as healthy, that the health topic
  is a second, unencrypted topic carrying the same recipients whose policy admits publishes from
  those five alarms alone, and that the key policy names the account root, the deploying role and
  EventBridge and nothing else.
- `terraform/tests/trail.tftest.hcl` asserts that a managed trail is this account's own, covers
  every region, logs, validates its files, and selects management events through exactly one
  advanced selector; that its bucket is closed, encrypted, expires its logs and refuses every
  caller not on TLS; that its Allow statements admit CloudTrail for this trail alone; and that
  `manage_trail` unset creates no trail while the three alerts exist either way.
- `tools/test_check_cloudtrail.sh` runs the trail gate's selector program against six trail
  shapes, including the two that exist and log yet record nothing the alerts need: a basic and an
  advanced trail that each select read-only events. A trail that excludes only KMS events still
  carries the alerts and is accepted.
- `terraform/tests/portability.tftest.hcl` renders the configuration with a GovCloud partition
  and region, with every computed ARN the policies name mocked in that partition, the alarms
  included, and fails if any policy the framework writes names the commercial partition. It also
  plans with `manage_trail` and `exempt_pipeline_roles` omitted to prove their defaults create no
  trail and exempt nobody, and renders the supplied-key mode in that partition.
- `terraform/tests/tagging.tftest.hcl` verifies that provider `default_tags` carries exactly the
  six identity keys and that the key, both topics, the queue, each rule, each alarm, and the
  trail and its bucket when managed carry them plus their own `Name`.
- `terraform/tests/validation.tftest.hcl` provides one negative run per validation rule:
  malformed and duplicate addresses, environment outside the lowercase set, every identity
  variable's accepted form, and a key alias that is empty, carries the `alias/` prefix, names an
  AWS-managed key, is written as an ARN, or is one character over KMS's limit, with the
  250-character name it accepts beside it.
- `make ci` also runs formatting, `terraform init`, validation, the offline trail-gate proof
  (`trail-check`), the region-and-partition tripwire (`portability-check`), TFLint,
  terraform-docs drift detection, documentation layout checks, and the bidirectional deny-all
  `.gitignore` allowlist guard.

## What The Tests Cannot Cover

Nothing here proves an event reaches an inbox. `plan`, `validate` and `terraform test` stop at
Terraform's own graph and never see CloudTrail hand an event to EventBridge, EventBridge publish
through the key, or SNS deliver. Two things stand in for that:

- The deploying runner proves the trail state the plan needs before applying and coverage after
  it, tests every planned pattern against EventBridge itself with the fixtures under
  `tools/fixtures/events/`, and reads every rule, its target, both topics, the subscriptions and
  the alarms back from AWS after applying. Validity of the input template and real delivery are
  the two properties no mock can reach; the template is covered by the JSON test plus the first
  real apply, delivery by the check below.
- The first apply is followed by one deliberate, harmless change per alert so that a real email
  is seen for each, and by one forced health alarm. That check is in the deployment guide.
