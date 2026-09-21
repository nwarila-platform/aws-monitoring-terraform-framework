# The framework writes a few ARNs itself: the key policy's account root, the deploying role, the
# trail, and its bucket. They must come from the provider's partition and region, so that
# providers.tf is the only file that changes between the lab and a GovCloud account. This suite
# renders every one of them under GovCloud and checks that nothing commercial leaks through.

mock_provider "aws" {
  alias = "us_east_1"

  mock_data "aws_partition" {
    defaults = {
      partition  = "aws-us-gov"
      dns_suffix = "amazonaws.com"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "us-gov-west-1"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = join("", ["123456", "789012"])
      arn        = "arn:aws-us-gov:sts::${join("", ["123456", "789012"])}:assumed-role/example-deploy-role/build-7"
    }
  }
}

variables {
  repository    = "infrastructure/aws/monitoring"
  repository_id = "4242"
  commit_sha    = "0123456789abcdef0123456789abcdef01234567"
  run_id        = "7"
  environment   = "prod"
  alert_emails  = ["security@example.com"]
}

run "every_arn_the_framework_writes_takes_the_providers_partition_and_region" {
  command = plan

  variables {
    manage_trail = true
  }

  assert {
    condition = alltrue([
      contains([for s in jsondecode(aws_kms_key.us_east_1.policy).Statement : s.Principal.AWS if s.Sid == "AccountAdministersTheKey"],
      "arn:aws-us-gov:iam::123456789012:root"),
      contains([for s in jsondecode(aws_kms_key.us_east_1.policy).Statement : s.Principal.AWS if s.Sid == "DeployRoleAdministersTheKey"],
      "arn:aws-us-gov:iam::123456789012:role/example-deploy-role"),
    ])
    error_message = "The key policy must name the account root and the deploying role in the provider's partition."
  }

  assert {
    condition = alltrue([
      for s in jsondecode(aws_s3_bucket_policy.us_east_1_trail[0].policy).Statement : alltrue([
        s.Condition.StringEquals["aws:SourceArn"] == "arn:aws-us-gov:cloudtrail:us-gov-west-1:123456789012:trail/management-events",
        startswith(s.Resource, "arn:aws-us-gov:s3:::123456789012-cloudtrail"),
      ])
    ])
    error_message = "The trail bucket policy must name the trail and the bucket in the provider's partition and region."
  }

  # The property that matters: no policy this framework writes names the commercial partition.
  assert {
    condition = alltrue([
      for document in [aws_kms_key.us_east_1.policy, aws_s3_bucket_policy.us_east_1_trail[0].policy] :
      !strcontains(document, "arn:aws:")
    ])
    error_message = "A GovCloud deployment must not produce a single commercial-partition ARN."
  }
}

# manage_trail and exempt_pipeline_roles are omitted here, so this run sees their defaults: the
# values a new account takes when its value file says nothing. Neither may create a trail or
# silence anyone.
run "omitted_values_fall_to_the_safe_defaults" {
  command = plan

  assert {
    condition     = length(aws_cloudtrail.us_east_1) == 0 && length(aws_s3_bucket.us_east_1_trail) == 0
    error_message = "By default the framework must not create a trail, which could bill management events twice."
  }

  assert {
    condition     = !can(jsondecode(aws_cloudwatch_event_rule.us_east_1["security-group"].event_pattern).detail["$or"])
    error_message = "By default nobody is exempt from the security-group alert."
  }
}
