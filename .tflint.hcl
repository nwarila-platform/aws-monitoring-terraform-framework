# Core Terraform rules only. This repo does not enable tflint-ruleset-aws
# because CI does not run `tflint --init` or download provider-specific
# plugins during `make ci`.
tflint {
  required_version = "= 0.62.0"
}

config {
  call_module_type = "none"
}
