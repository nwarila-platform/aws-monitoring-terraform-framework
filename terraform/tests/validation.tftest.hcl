mock_provider "aws" {
  alias = "us_east_1"

  # The commercial partition and region, so every ARN the framework writes renders the way a
  # commercial deployment sees it. tests/portability.tftest.hcl renders the GovCloud case.
  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }

  # IAM's answer for the deploying session's role.
  mock_data "aws_iam_session_context" {
    defaults = {
      issuer_arn = "arn:aws:iam::${join("", ["123456", "789012"])}:role/example-deploy-role"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = join("", ["123456", "789012"])
      arn        = "arn:aws:sts::${join("", ["123456", "789012"])}:assumed-role/example-deploy-role/aws-deploy-42"
    }
  }
}

variables {
  repository            = "example-org/aws-monitoring"
  repository_id         = "123456789"
  commit_sha            = "0123456789abcdef0123456789abcdef01234567"
  run_id                = "42"
  environment           = "test"
  manage_trail          = false
  exempt_pipeline_roles = []
  alert_emails          = ["security@example.com"]
}

run "rejects_an_address_without_a_domain" {
  command = plan

  variables {
    alert_emails = ["security"]
  }

  expect_failures = [var.alert_emails]
}

run "rejects_an_address_with_whitespace" {
  command = plan

  variables {
    alert_emails = ["security @example.com"]
  }

  expect_failures = [var.alert_emails]
}

run "rejects_the_same_address_twice" {
  command = plan

  variables {
    alert_emails = ["security@example.com", "security@example.com"]
  }

  expect_failures = [var.alert_emails]
}

run "rejects_environment_outside_lowercase_set" {
  command = plan

  variables {
    environment = "staging"
  }

  expect_failures = [var.environment]
}

# Case variants are rejected too: the value reaches the Environment tag verbatim, so "dev" and
# "DEV" would otherwise be two different values in every tag-based inventory query.
run "rejects_uppercase_environment_case_variant" {
  command = plan

  variables {
    environment = "DEV"
  }

  expect_failures = [var.environment]
}

run "rejects_an_uppercase_commit_sha" {
  command = plan

  variables {
    commit_sha = "ABC123"
  }

  expect_failures = [var.commit_sha]
}

run "rejects_non_numeric_repository_id" {
  command = plan

  variables {
    repository_id = "not-a-number"
  }

  expect_failures = [var.repository_id]
}

run "rejects_non_numeric_run_id" {
  command = plan

  variables {
    run_id = "run-42"
  }

  expect_failures = [var.run_id]
}

run "rejects_repository_without_owner" {
  command = plan

  variables {
    repository = "aws-monitoring-terraform-framework"
  }

  expect_failures = [var.repository]
}

run "rejects_metadata_tag_value_over_256_characters" {
  command = plan

  variables {
    repository_id = join("", [for index in range(257) : "1"])
  }

  expect_failures = [var.repository_id]
}

# A prod deployment with nobody subscribed applies green and can never email anyone.
run "rejects_prod_with_no_recipients" {
  command = plan

  variables {
    environment  = "prod"
    alert_emails = []
  }

  expect_failures = [var.alert_emails]
}

run "accepts_an_empty_recipient_list_outside_prod" {
  command = plan

  variables {
    environment  = "dev"
    alert_emails = []
  }

  assert {
    condition     = length(aws_sns_topic_subscription.us_east_1) == 0
    error_message = "dev and test may bootstrap with no recipients."
  }
}

run "rejects_an_exempt_role_written_as_an_arn" {
  command = plan

  variables {
    exempt_pipeline_roles = ["arn:aws:iam::123456789012:role/example-ci-role"]
  }

  expect_failures = [var.exempt_pipeline_roles]
}

run "rejects_the_same_exempt_role_twice" {
  command = plan

  variables {
    exempt_pipeline_roles = ["example-ci-role", "example-ci-role"]
  }

  expect_failures = [var.exempt_pipeline_roles]
}

# A GitLab project in a subgroup is a legitimate source; only a single segment is rejected.
run "accepts_a_repository_path_nested_in_subgroups" {
  command = plan

  variables {
    repository = "infrastructure/aws/monitoring"
  }

  assert {
    condition     = local.identity_tags["Repository"] == "infrastructure/aws/monitoring"
    error_message = "A nested repository path must reach the Repository tag unchanged."
  }
}

run "rejects_a_repository_path_with_a_leading_slash" {
  command = plan

  variables {
    repository = "/group/repository"
  }

  expect_failures = [var.repository]
}

run "rejects_a_repository_path_with_a_trailing_slash" {
  command = plan

  variables {
    repository = "group/repository/"
  }

  expect_failures = [var.repository]
}

run "rejects_a_repository_path_with_an_empty_segment" {
  command = plan

  variables {
    repository = "group//repository"
  }

  expect_failures = [var.repository]
}

run "rejects_a_repository_path_that_climbs" {
  command = plan

  variables {
    repository = "group/../repository"
  }

  expect_failures = [var.repository]
}

run "rejects_a_repository_path_with_a_dot_segment" {
  command = plan

  variables {
    repository = "group/./repository"
  }

  expect_failures = [var.repository]
}

# A naming convention is a valid exemption, so a fleet's pipelines stay covered as it grows.
run "accepts_an_exempt_role_pattern" {
  command = plan

  variables {
    exempt_pipeline_roles = ["example-org_*_runner"]
  }

  assert {
    condition = jsondecode(aws_cloudwatch_event_rule.us_east_1["security-group"].event_pattern).detail["$or"][0].userIdentity.sessionContext.sessionIssuer.userName == [
      { "anything-but" = { wildcard = ["example-org_*_runner"] } }
    ]
    error_message = "A role pattern must reach the security-group rule as an anything-but wildcard."
  }
}

# A lone wildcard would match every assumed-role session, people included.
run "rejects_an_exempt_pattern_that_matches_everyone" {
  command = plan

  variables {
    exempt_pipeline_roles = ["*"]
  }

  expect_failures = [var.exempt_pipeline_roles]
}

run "rejects_consecutive_wildcards" {
  command = plan

  variables {
    exempt_pipeline_roles = ["example-org_**_runner"]
  }

  expect_failures = [var.exempt_pipeline_roles]
}
