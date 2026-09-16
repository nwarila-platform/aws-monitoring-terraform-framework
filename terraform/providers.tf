provider "aws" {

  alias = "us_east_1"

  region = "us-east-1"

  # The six identity keys go on every resource, including ones whose own tags block would be
  # applied by a separate tagging call after creation. A deploy role that conditions creation on
  # aws:RequestTag/RepositoryId depends on the key being in the create request itself.
  default_tags {
    tags = local.identity_tags
  }

}
