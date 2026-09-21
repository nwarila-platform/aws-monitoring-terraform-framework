# Partial S3 backend; real values arrive via -backend-config (see backend.hcl.example).
# Bucket identities never live in-repo.

terraform {

  # PARTIAL by design, split along ownership: the framework fixes the invariants that hold for
  # EVERY deployment, and the runner supplies only what is specific to its account (bucket, key,
  # region) via -backend-config. `encrypt` is set here rather than merely documented because org
  # state buckets deny uploads whose REQUEST carries no x-amz-server-side-encryption header, and
  # bucket-default encryption does not satisfy that condition.
  backend "s3" {
    encrypt      = true
    use_lockfile = true # S3-native state locking (Terraform >= 1.10); no DynamoDB table
  }

}
