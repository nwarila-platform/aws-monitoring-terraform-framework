# AWS IAM reference

The IAM the deploy workflow runs with. **These documents are the proposed specification, not an
export**: the role does not exist yet. Two substitutions are written as placeholders,
`<account-id>` and `<repository-id>`, the latter being the numeric GitHub repository id that
exists only once the repository is created. Terraform does not manage any of this; an operator
applies it, and once it is live the documents here are replaced by an export from the account so
that they describe what is deployed rather than what was intended.

## Roles

| Role | Trusted by | Attached policies | Does |
|---|---|---|---|
| `nwarila-platform_aws-cloudwatch-framework_runner` | GitHub OIDC: `aws-deploy.yaml` on `main` | the five `…_runner_*` | Prove the trail, plan, apply, verify |

No inline policies.

## Boundaries in the documents

- Every statement is `Allow`; none is `Deny`.
- **The OIDC trust** requires the `sts.amazonaws.com` audience, this repository's id, the
  `refs/heads/main` ref, one of the two `sub` forms GitHub issues for it, and a
  `job_workflow_ref` naming the one workflow that deploys. A branch, a fork, or another workflow
  in this repository cannot assume the role.
- **Creating the key, the topic, and each rule** requires the `RepositoryId` request tag, which
  the provider's `default_tags` places in every create call. Operating on the key and the rules
  afterwards is conditioned on the `RepositoryId` resource tag; the topic and its subscriptions
  are addressed by exact ARN instead, because SNS names are fixed.
- **The alias** is the one name `alias/security-change-alerts`; the rules are the one prefix
  `security-change-alerts-*`.
- **CloudTrail** access is three read calls on `*`, which is the least `DescribeTrails` accepts.
- **State** is read and write on the one state object and its lock, with listing limited to those
  two keys.

## Accepted residuals

- `kms:CreateKey` and `kms:ListAliases` cannot be scoped below `*`; the request-tag condition on
  `CreateKey` is what bounds it.
- The `sub` claim's organisation-id form (`nwarila-platform@230745524`) is the one GitHub issues
  for this organisation; it is copied from the sibling repositories' live trusts.

## Creating the role

```sh
account_id=<account-id>
repository_id=<numeric id from: gh api repos/nwarila-platform/aws-cloudwatch-framework --jq .id>
role=nwarila-platform_aws-cloudwatch-framework_runner

sub() { sed "s/<account-id>/${account_id}/g; s/<repository-id>/${repository_id}/g" "$1"; }

aws iam create-role --role-name "${role}" \
  --assume-role-policy-document "$(sub roles/${role}.trust.json)"
for policy in cloudtrail events kms s3 sns; do
  arn="$(aws iam create-policy --policy-name "${role}_${policy}" \
    --policy-document "$(sub policies/${role}_${policy}.json)" --query Policy.Arn --output text)"
  aws iam attach-role-policy --role-name "${role}" --policy-arn "${arn}"
done
```

Then set the repository secret `AWS_ACCOUNT_ID` and dispatch `AWS Deploy`.
