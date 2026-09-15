# Terraform Runner Protocol

This repository supplies a Terraform root module under `terraform/` and the one workflow that
deploys it, `.github/workflows/aws-deploy.yaml`. The workflow is the runner: it owns checkout,
authentication, the backend values, the identity arguments, and post-apply verification. This
page is the contract a workstation plan has to honour to behave the same way.

## Backend Configuration

The module declares a partial S3 backend in `terraform/backend.tf`. The runner supplies bucket,
key, and region. The workflow uses `<account-id>-terraform` and the key
`nwarila-platform/aws-cloudwatch-framework/terraform.tfstate`; a workstation starts from
`terraform/backend.hcl.example`, and `terraform/backend.hcl` is ignored so bucket identities do
not enter source control.

```shell
cp terraform/backend.hcl.example terraform/backend.hcl
terraform -chdir=terraform init -backend-config=backend.hcl
```

Backend encryption and S3-native locking are invariants declared in `terraform/backend.tf`.

## Terraform Inputs

`terraform/terraform.tfvars` is committed and loaded automatically. It carries the environment
and the recipients, and nothing else.

## Deployment Identity

Every plan requires these four command-line variables. All are mandatory and non-nullable; there
is no unattributed deployment:

- `repository`: the source repository as an `owner/name` slug.
- `repository_id`: the numeric, rename-stable GitHub repository id.
- `commit_sha`: the lowercase SHA of the checked-out commit.
- `run_id`: the numeric GitHub Actions run id, or another numeric run identifier for local use.

Pass them as command-line `-var` arguments so they outrank the value file. Capture the
checked-out commit with `git rev-parse HEAD`; on pull requests, `github.sha` may identify a
synthetic merge commit instead.

```yaml
- name: Terraform plan
  run: |
    terraform -chdir=terraform plan -input=false -out=tfplan \
      -var "commit_sha=$(git rev-parse HEAD)" \
      -var "repository=${GITHUB_REPOSITORY}" \
      -var "repository_id=${GITHUB_REPOSITORY_ID}" \
      -var "run_id=${GITHUB_RUN_ID}"
```

The module writes `ManagedBy`, `Repository`, `RepositoryId`, `Environment`, `CommitSha`, and
`RunId` into the tag map of every taggable resource, alongside `Name`, and additionally sets the
six uniform keys as provider `default_tags` so they travel in the create request where the
deploy role's tag conditions can see them.

Because `CommitSha` and `RunId` change per deployment, a standing estate sees in-place tag
updates on every deploy. That is the record working as intended.

## Runner Responsibilities

- checking out the reviewed commit on `refs/heads/main`;
- assuming the deploy role over OIDC and supplying the partial backend values;
- proving a logging CloudTrail trail covers the region (`tools/check_cloudtrail.sh`);
- supplying the four identity arguments on plan;
- applying the saved plan; and
- reading the rules, target, key, and subscriptions back from AWS and failing on any mismatch.
