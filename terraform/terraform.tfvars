# The one deployment this repository owns. Deployment identity (repository, repository_id,
# commit_sha, run_id) is NOT set here: the deploy workflow passes it as command-line -var
# arguments, which outrank this file, so a value file cannot restate who deployed.

# Exactly one of dev, test, or prod (lowercase). The alerts protect the real account, so prod.
environment = "prod"

# Who is emailed on every security group and IAM change. Each address must confirm the
# subscription SNS emails it before anything is delivered. A prod deployment requires at least
# one address, so the first recipient lands in the same change that first deploys.
alert_emails = ["REPLACE_ME@example.com"]

# The deploy pipelines whose security-group churn is not emailed, measured from 30 days of
# CloudTrail. Their IAM changes still alert, and so does every change made by a person. Adding a
# repository to the fleet means adding its runner role here.
exempt_pipeline_roles = [
  "nwarila-platform_aws-workspace-builder_runner",
  "nwarila-platform_jenkins_runner",
  "nwarila-platform_keycloak_runner",
  "nwarila-platform_nessus_runner",
  "nwarila-platform_pdq-deploy-inventory_runner",
  "nwarila-platform_rancher_runner",
  "nwarila-platform_windows-fileserver-ha_runner",
  "nwarila-platform_windows-wsus_runner",
]
