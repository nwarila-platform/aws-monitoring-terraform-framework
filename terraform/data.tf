# Facts about the account and the provider's target, read rather than written so that providers.tf
# is the only file that differs between deployments.


#region ------ [ aws_caller_identity ] --------------------------------------------------------- #

#region ------ [ aws_caller_identity.current - us-east-1 ] ------------------------------------- #

data "aws_caller_identity" "current" {

  # The account the runner deploys into. The KMS key policy names its root principal, which is
  # what keeps the key administrable after the runner's session ends.
  provider = aws.us_east_1

}

#endregion --- [ aws_caller_identity.current - us-east-1 ] ------------------------------------- #

#endregion --- [ aws_caller_identity ] --------------------------------------------------------- #


#region ------ [ aws_iam_session_context ] ----------------------------------------------------- #

#region ------ [ aws_iam_session_context.current - us-east-1 ] --------------------------------- #

data "aws_iam_session_context" "current" {

  # Read only where the framework writes a key policy that must name the deploying role, so a
  # deployment that supplies its own key needs no iam:GetRole at all.
  provider = aws.us_east_1
  for_each = local.framework_key_names

  # The role behind the deploying session, asked of IAM rather than rebuilt from the session ARN,
  # which drops the role's path. A role under any path is named correctly; a caller that is not an
  # assumed role comes back unchanged.
  arn = data.aws_caller_identity.current.arn

}

#endregion --- [ aws_iam_session_context.current - us-east-1 ] --------------------------------- #

#endregion --- [ aws_iam_session_context ] ----------------------------------------------------- #


#region ------ [ aws_kms_key ] ----------------------------------------------------------------- #

#region ------ [ aws_kms_key.us_east_1_alert - us-east-1 ] ------------------------------------- #

data "aws_kms_key" "us_east_1_alert" {

  # Iterate through the supplied Alert Topic Key in the provider's region.
  provider = aws.us_east_1
  for_each = local.supplied_key_aliases

  # Define the Supplied Key Lookup Properties. DescribeKey resolves an alias to the key behind it
  # and is the only call this makes; the alias belongs to this account and region by definition.
  key_id = "alias/${each.value}"

  lifecycle {
    # SNS encrypts a topic with a symmetric key only, and a key that is not enabled cannot be used
    # to publish. Both faults deploy cleanly and deliver nothing, so they fail here instead.
    postcondition {
      condition     = self.key_spec == "SYMMETRIC_DEFAULT"
      error_message = "alert_key_alias names a ${self.key_spec} key; SNS encrypts a topic with a SYMMETRIC_DEFAULT key only."
    }

    postcondition {
      condition     = self.key_state == "Enabled"
      error_message = "alert_key_alias names a key in state ${self.key_state}; only an Enabled key can encrypt the alert topic."
    }
  }

}

#endregion --- [ aws_kms_key.us_east_1_alert - us-east-1 ] ------------------------------------- #

#endregion --- [ aws_kms_key ] ----------------------------------------------------------------- #


#region ------ [ aws_partition ] --------------------------------------------------------------- #

#region ------ [ aws_partition.current - us-east-1 ] ------------------------------------------- #

data "aws_partition" "current" {

  # Every ARN this framework writes itself takes its partition from here, so the same code names
  # the right principals and resources in the commercial and GovCloud partitions alike.
  provider = aws.us_east_1

}

#endregion --- [ aws_partition.current - us-east-1 ] ------------------------------------------- #

#endregion --- [ aws_partition ] --------------------------------------------------------------- #


#region ------ [ aws_region ] ------------------------------------------------------------------ #

#region ------ [ aws_region.current - us-east-1 ] ---------------------------------------------- #

data "aws_region" "current" {

  # The region the provider targets, for the one ARN that must name it before the resource exists.
  provider = aws.us_east_1

}

#endregion --- [ aws_region.current - us-east-1 ] ---------------------------------------------- #

#endregion --- [ aws_region ] ------------------------------------------------------------------ #
