# Testing Strategy

## What The Tests Cover

`terraform test` runs with a mocked AWS provider, so the tests exercise Terraform configuration
behavior without making AWS API calls.

- `terraform/tests/alerts.tftest.hcl` pins each rule's event pattern to its exact list of write
  calls, asserts the rules are `ENABLED` on the default bus, that every rule targets the one
  topic through the transformer, that the template quotes every input path, that the key policy
  admits EventBridge without a condition and keeps the account root, that the topic policy admits
  EventBridge only, that each address is one email subscription, that no addresses means no
  subscriptions and nothing else changes, and that the outputs record it all.
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

- The deploy workflow proves a logging trail exists before applying, and reads every rule, its
  target, the topic's key and the subscriptions back from AWS after applying.
- The first apply is followed by a deliberate, harmless change to a security group so that a
  real email is seen. That check is in
  [deploy and confirm recipients](../how-to/deploy-and-confirm-recipients.md).
