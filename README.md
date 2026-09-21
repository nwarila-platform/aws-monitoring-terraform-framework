# aws-monitoring-terraform-framework

Terraform framework for monitoring and alerting on one AWS account, in the region its
`providers.tf` targets. It is deliberately small: today it emails a list of recipients whenever a
security group or
IAM permissions change, and it is shaped so that further alerts are added by naming the API
calls that count, not by writing new plumbing.

Each alert is an EventBridge rule matching the CloudTrail record of the change, publishing to one
KMS-encrypted SNS topic that emails every subscribed recipient. The email is a JSON message
carrying the call, the account, the region, the time, and the whole CloudTrail record, so the
reader knows what changed and who changed it before opening the console. Undeliverable alerts
land in a dead-letter queue, and alarms report delivery failures to a separate health topic.
When asked, the framework also creates the multi-region CloudTrail trail the alerts depend on.

This repository is the framework, not a deployment. A deployment pins a commit of it and supplies
one value file per environment; nothing outside `terraform/providers.tf` names a region or an ARN
partition, so the same commit deploys to a commercial or a GovCloud account by changing only that
file. See the [runner protocol](docs/reference/runner-protocol.md).

## Quickstart

### Contributor check

Run the local quality gate before changing Terraform sources:

```shell
make ci
```

The CI path runs Terraform formatting, init, validation, tests, the offline trail-gate proof,
TFLint, terraform-docs drift detection, documentation layout checks, and the bidirectional
deny-all `.gitignore` allowlist guard.

### Plan from a workstation

```shell
cp terraform/backend.hcl.example terraform/backend.hcl
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
terraform -chdir=terraform init -backend-config=backend.hcl

identity=(
  -var="repository=<owner>/<runner repository>"
  -var="repository_id=<numeric repository id>"
  -var="commit_sha=$(git rev-parse HEAD)"
  -var="run_id=0"
)

terraform -chdir=terraform plan "${identity[@]}"
```

`repository`, `repository_id`, `commit_sha`, and `run_id` are required and are deliberately absent
from the example value file. They become the `Repository`, `RepositoryId`, `CommitSha`, and
`RunId` provenance tags on every resource, so a value file must not be able to restate them.

## Documentation

- [Getting started](docs/how-to/develop-this-module.md)
- [Architecture](docs/explanation/architecture.md)
- [Threat model](docs/explanation/threat-model.md)
- [Runner protocol](docs/reference/runner-protocol.md)
- [Terraform reference](docs/reference/terraform.md)
- [Release gates](docs/reference/release-gates.md)
