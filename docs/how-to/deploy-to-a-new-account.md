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
   - If it fails and `aws cloudtrail list-trails` returns nothing, the account has no trail: set
     `manage_trail = true` and the framework creates one.
   - If it fails and a trail exists, that trail records too little, for example only read
     events. Fix its event selectors rather than adding a second trail, which bills every
     management event twice.
5. **Write the value file.** Set `environment` and at least one address in `alert_emails`. Leave
   `exempt_pipeline_roles` unset, so every change alerts.

## After the first apply

1. **Confirm the subscriptions.** Each recipient receives two confirmation emails, one for alerts
   and one for channel health, and nothing is delivered until both are followed. This lists any
   still pending:

   ```sh
   aws sns list-subscriptions --query \
     "Subscriptions[?contains(TopicArn, ':security-change-alerts') && SubscriptionArn=='PendingConfirmation']"
   ```

2. **Prove delivery.** As a person, not the pipeline, create a security group in the provider's
   region and delete it. Within a few minutes each recipient receives a message headed
   `Security group changed`. If none arrives, the rule's `FailedInvocations` metric and the queue
   `security-change-alerts-dlq` say where it stopped.
3. **Close the other regions.** A security-group change in any other region raises no alert.
   Deny resource creation outside the provider's region with an account control, as the
   [invariants](../reference/invariants.md) require, or record the gap as accepted.
