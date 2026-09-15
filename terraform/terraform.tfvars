# The one deployment this repository owns. Deployment identity (repository, repository_id,
# commit_sha, run_id) is NOT set here: the deploy workflow passes it as command-line -var
# arguments, which outrank this file, so a value file cannot restate who deployed.

# Exactly one of dev, test, or prod (lowercase). The alerts protect the real account, so prod.
environment = "prod"

# Who is emailed on every security group and IAM role change. Each address must confirm the
# subscription SNS emails it before anything is delivered. Empty until the recipients are agreed.
alert_emails = []
