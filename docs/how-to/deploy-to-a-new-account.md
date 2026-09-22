# Deploy to a new account

Each account is deployed on its own, with its own value file, state, and deploy role. Do these
steps once per account, in order, before its pipeline applies for the first time. A pipeline that
runs only `init`, `plan`, and `apply` cannot make these checks, so a person makes them here.

## Before the first apply

1. **Point the provider at the partition's global-service region.** CloudTrail delivers IAM
   events only there: `us-east-1` in the commercial partition, `us-gov-west-1` in GovCloud. Set
   that region in `terraform/providers.tf`. The IAM rule refuses any other region at plan time.
2. **Configure the backend.** Supply the state bucket, key, and region as the
   [runner protocol](../reference/runner-protocol.md#backend-configuration) describes, starting
   from `terraform/backend.hcl.example`.
3. **Create the deploy role.** Grant it
   [the calls the runner protocol lists](../reference/runner-protocol.md#deploy-role-permissions),
   in the account's own partition, including `iam:GetRole` on the role itself. A role without it
   fails the first plan.
4. **Decide the trail.** With read credentials for the account, run:

   ```sh
   AWS_REGION=<region> tools/check_cloudtrail.sh
   ```

   - If it passes, a trail already carries the alerts: leave `manage_trail` unset.
   - If it fails and `aws cloudtrail list-trails --region <region>` returns nothing, the account
     has no trail: set `manage_trail = true` and the framework creates one.
   - If it fails and a trail exists, that trail is missing something the alerts need: it may be
     stopped, cover another region only, omit global service events, or record read events only.
     The script names the first two cases; inspect the trail for the others. Fix that trail rather
     than adding a second one, which is billed for every management event both copies record.
5. **Write the value file.** Set `environment` and at least one address in `alert_emails`. Leave
   `exempt_pipeline_roles` unset, so every change alerts.

## After the first apply

1. **Confirm the subscriptions.** Each recipient receives two confirmation emails, one for alerts
   and one for channel health. Each topic begins delivering as soon as its own subscription is
   confirmed, so an unconfirmed health subscription silences the alarms alone. This lists what is
   still pending, using the deploy role's own read of each topic:

   ```sh
   for arn in "$(terraform output -raw alert_topic_arn)" "$(terraform output -raw health_topic_arn)"; do
     aws sns list-subscriptions-by-topic --region <region> --topic-arn "${arn}" \
       --query "Subscriptions[?SubscriptionArn=='PendingConfirmation'].Endpoint"
   done
   ```

2. **Prove delivery, for both alerts.** As a person, not the pipeline, create a security group in
   the provider's region and delete it, then tag and untag a scratch IAM role. Within a few
   minutes each recipient receives a message for each call, whose first field is
   `"alert": "Security group changed"` or `"alert": "IAM permissions changed"`. The second proves
   the IAM rule, whose events reach only the partition's global-service region. If a message is
   missing, work along the path: the call in CloudTrail event history, then the rule's
   `MatchedEvents` and `Invocations`, then its `FailedInvocations` and the queue
   `security-change-alerts-dlq`, then the topic's subscription state and
   `NumberOfNotificationsFailed`.
3. **Close the other regions.** A security-group change in any other region raises no alert.
   Deny resource creation outside the provider's region with an account control, as the
   [invariants](../reference/invariants.md) require, or record the gap as accepted.
