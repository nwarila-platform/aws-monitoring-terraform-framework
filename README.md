# aws-cloudwatch-framework

Terraform framework for the monitoring and alerting of one AWS account in the supported
`us_east_1` region. It is deliberately small: today it emails a list of recipients whenever a
security group or an IAM role changes, and it is shaped so that further alerts are added by
naming the API calls that count, not by writing new plumbing.

Each alert is an EventBridge rule matching the CloudTrail record of the change, publishing to
one KMS-encrypted SNS topic that emails every subscribed recipient. The email names the
principal, the API call, the source address, the time, and the request parameters, so the
reader knows what changed and who changed it before opening the console.

This repository is its own deployment root: it owns the one deployment of these alerts and
applies it from GitHub Actions on every merge to `main`. It does not own the CloudTrail trail
whose events it consumes; the deploy proves a logging trail exists before it touches state.

## Quickstart

### Contributor check

Run the local quality gate before changing Terraform sources:

```shell
make ci
```

The CI path runs Terraform formatting, init, validation, tests, TFLint, terraform-docs drift
detection, documentation layout checks, and the bidirectional deny-all `.gitignore` allowlist
guard.

### Deploy

The deploy workflow applies `main`. To plan the same thing from a workstation, supply the
backend and the deployment identity that the workflow would:

```shell
cp terraform/backend.hcl.example terraform/backend.hcl
terraform -chdir=terraform init -backend-config=backend.hcl

identity=(
  -var="repository=nwarila-platform/aws-cloudwatch-framework"
  -var="repository_id=<numeric repository id>"
  -var="commit_sha=$(git rev-parse HEAD)"
  -var="run_id=0"
)

terraform -chdir=terraform plan "${identity[@]}"
```

`repository`, `repository_id`, `commit_sha`, and `run_id` are required and are deliberately
absent from `terraform.tfvars`. They become the `Repository`, `RepositoryId`, `CommitSha`, and
`RunId` provenance tags on every resource, so a value file must not be able to restate them.
Omitting them fails the plan, which is the intended behavior.

Recipients live in `terraform/terraform.tfvars` as `alert_emails`. Each address receives a
confirmation email from SNS after apply and is delivered nothing until it follows the link. See
[deploy and confirm recipients](docs/how-to/deploy-and-confirm-recipients.md).

## Documentation

- [Getting started](docs/how-to/develop-this-module.md)
- [Deploy and confirm recipients](docs/how-to/deploy-and-confirm-recipients.md)
- [Architecture](docs/explanation/architecture.md)
- [Threat model](docs/explanation/threat-model.md)
- [Terraform reference](docs/reference/terraform.md)
- [AWS IAM reference](docs/reference/aws-iam/README.md)
- [Release gates](docs/reference/release-gates.md)
