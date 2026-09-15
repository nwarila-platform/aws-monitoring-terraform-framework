provider "aws" {

  alias = "us_east_1"

  region = "us-east-1"

  # Identity travels in the create request, which is the only place a tag-conditioned IAM policy
  # can see it. A resource's own tags block is applied afterwards by a separate tagging call and
  # never reaches the request. See local.identity_tags.
  default_tags {
    tags = local.identity_tags
  }

}
