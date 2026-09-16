# Pre-existing infrastructure lookups.


#region ------ [ aws_caller_identity ] --------------------------------------------------------- #

data "aws_caller_identity" "current" {

  # The account the runner deploys into. The KMS key policy names its root principal, which is
  # what keeps the key administrable after the runner's session ends.
  provider = aws.us_east_1

}

#endregion --- [ aws_caller_identity ] --------------------------------------------------------- #
