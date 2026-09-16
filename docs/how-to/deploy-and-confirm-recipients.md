# Deploy and confirm recipients

## Before the first deploy

The deploy workflow needs three things that this repository does not create:

1. **A logging CloudTrail trail** covering `us-east-1` with global service events included and
   write management events recorded. Check with the same script the workflow runs:

   ```sh
   AWS_REGION=us-east-1 tools/check_cloudtrail.sh
   ```

   If it reports none, leave `manage_trail = true` and this deployment creates one. If the
   account already has a covering trail, set `manage_trail = false`: a second trail bills every
   management event twice. The deploy checks which case it is in before applying.

2. **The deploy role.** Create `nwarila-platform_aws-cloudwatch-framework_runner` from the
   documents under [`docs/reference/aws-iam/`](../reference/aws-iam/README.md), substituting
   the account id and the repository's numeric id.

3. **The repository secret** `AWS_ACCOUNT_ID`, holding the workload account id.

## Adding recipients

1. Add each address to `alert_emails` in `terraform/terraform.tfvars`. A `prod` deployment with
   an empty list is rejected at plan, because it would apply green and email nobody.
2. Open a PR. `CI` validates the addresses; review the list as the access decision it is.
3. Merge. `AWS Deploy` proves the trail, proves every pattern against EventBridge, applies, then
   fails if fewer subscriptions exist than recipients configured. Its job summary lists every
   subscription and whether it is still pending.
4. Each recipient receives "AWS Notification - Subscription Confirmation" from
   `no-reply@sns.amazonaws.com` and must follow the link. A pending subscription delivers
   nothing and expires after three days; re-running the deploy re-sends it.

## Seeing a real alert

Terraform proves the wiring, not delivery. After the first confirmed subscription, make one
harmless change and wait for the email:

```sh
aws ec2 create-tags --resources sg-<any group> --tags Key=AlertCheck,Value=1   # no email: tags are not a rule change
aws ec2 update-security-group-rule-descriptions-egress --group-id sg-<any group> \
  --security-group-rules SecurityGroupRuleId=sgr-<any rule>,Description="alert check"
```

The second call is on the security-group alert's list and should arrive within a minute or two,
as a JSON message whose `alert` field reads "Security group changed" and whose `event` field
carries the whole CloudTrail record, including your principal. Revert the description afterwards.

Make that change as yourself, not from a pipeline. A role named in `exempt_pipeline_roles` is
exempt from the security-group alert by design and will produce no email. If nothing arrives, check in this order: the subscription is confirmed, the trail
check passes, the rule shows a non-zero `Invocations` metric in CloudWatch, and the topic's
`NumberOfNotificationsFailed` metric is zero.

## Removing a recipient

Delete the address from `alert_emails` and merge. Terraform unsubscribes it; a confirmed
subscription is removed immediately, a pending one is simply not renewed.
