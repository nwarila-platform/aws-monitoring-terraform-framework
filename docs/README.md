# Documentation

Documentation for this repository follows the [Diataxis framework](https://diataxis.fr/)
per
[org ADR-0002](https://github.com/nwarila-platform/.github/blob/main/docs/decision-records/0002-adopt-diataxis-documentation-framework.md).

| Quadrant     | Path                  | Purpose                              |
| ------------ | --------------------- | ------------------------------------ |
| Explanation  | `explanation/`        | Architecture, threat model, testing  |
| Reference    | `reference/`          | Generated terraform docs, invariants |
| How-to       | `how-to/`             | Task-oriented guides                 |
| Decisions    | `decision-records/`   | ADR index and repo ADRs              |

## How-to guides

- [Develop this module](how-to/develop-this-module.md)
- [Deploy and confirm recipients](how-to/deploy-and-confirm-recipients.md)

## Explanation

- [Architecture](explanation/architecture.md)
- [Testing strategy](explanation/testing-strategy.md)
- [Threat model](explanation/threat-model.md)

## Reference

- [AWS IAM](reference/aws-iam/README.md)
- [Invariants](reference/invariants.md)
- [Mirroring](reference/mirroring.md)
- [Release gates](reference/release-gates.md)
- [Runner protocol](reference/runner-protocol.md)
- [Style guide](reference/style-guide.md)
- [Terraform reference](reference/terraform.md) (generated)

## Decisions

- [ADR index](decision-records/README.md)
