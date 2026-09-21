# Facts about the account and the provider's target, read rather than written so that providers.tf
# is the only file that differs between deployments.


#region ------ [ aws_caller_identity ] --------------------------------------------------------- #

data "aws_caller_identity" "current" {

  # The account the runner deploys into. The KMS key policy names its root principal, which is
  # what keeps the key administrable after the runner's session ends.
  provider = aws.us_east_1

}

#endregion --- [ aws_caller_identity ] --------------------------------------------------------- #


#region ------ [ aws_partition ] --------------------------------------------------------------- #

data "aws_partition" "current" {

  # Every ARN this framework writes itself takes its partition from here, so the same code names
  # the right principals and resources in the commercial and GovCloud partitions alike.
  provider = aws.us_east_1

}

#endregion --- [ aws_partition ] --------------------------------------------------------------- #


#region ------ [ aws_region ] ------------------------------------------------------------------ #

data "aws_region" "current" {

  # The region the provider targets, for the one ARN that must name it before the resource exists.
  provider = aws.us_east_1

}

#endregion --- [ aws_region ] ------------------------------------------------------------------ #
