# Testing Strategy

## What The Tests Cover

`terraform test` runs with a mocked AWS provider, so the tests exercise Terraform configuration
behavior without making AWS API calls.

- `terraform/tests/alerts.tftest.hcl` pins each rule's event pattern to its exact list of write
  calls, pins both branches of the pipeline exemption and proves IAM carries none, asserts the
  rules are `ENABLED` on the default bus, that every rule targets the one topic through the
  transformer, that each template is valid JSON once its placeholders are substituted, that the
  key policy admits EventBridge without a condition and keeps the account root, that the topic
  policy admits EventBridge only, that each address is one email subscription, that no addresses
  means no subscriptions and nothing else changes, and that the outputs record it all.
- The reliability runs in `alerts.tftest.hcl` assert the dead-letter queue is wired to every
  target with a one-hour retry window, that its policy names only this framework's rules, that
  all four alarms report to the health topic and treat missing data as healthy, and that the
  health topic is a second encrypted topic carrying the same recipients.
- `tools/test_check_cloudtrail.sh` runs the trail gate's selector program against seven trail
  shapes, including the two that would otherwise pass while recording nothing the alerts need: a
  trail logging only read events, and one whose selectors exclude the alerted services.
- `terraform/tests/portability.tftest.hcl` renders the configuration with a GovCloud partition
  and region and fails if any policy the framework writes names the commercial partition. It also
  plans with `manage_trail` and `exempt_pipeline_roles` omitted to prove their defaults create no
  trail and exempt nobody.
- `terraform/tests/tagging.tftest.hcl` verifies that provider `default_tags` carries exactly the
  six identity keys and that the key, the topic and each rule carry them plus their own `Name`.
- `terraform/tests/validation.tftest.hcl` provides one negative run per validation rule:
  malformed and duplicate addresses, environment outside the lowercase set, and every identity
  variable's accepted form.
- `make ci` also runs formatting, `terraform init`, validation, TFLint, terraform-docs drift
  detection, documentation layout checks, and the bidirectional deny-all `.gitignore` allowlist
  guard.

## What The Tests Cannot Cover

Nothing here proves an event reaches an inbox. `plan`, `validate` and `terraform test` stop at
Terraform's own graph and never see CloudTrail hand an event to EventBridge, EventBridge publish
through the key, or SNS deliver. Two things stand in for that:

- The deploying runner proves a logging trail exists before applying, tests every planned pattern
  against EventBridge itself with the fixtures under `tools/fixtures/events/`, and reads every
  rule, its target, the topic's key and the subscriptions back from AWS after applying.
  Validity of the input template and real delivery are the two properties no mock can reach; the
  template is covered by the JSON test plus the first real apply, delivery by the check below.
- The first apply is followed by a deliberate, harmless change to a security group so that a
  real email is seen. That check is in
  the runner's deploy guide.
