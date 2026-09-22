# Exact toolchain pins. The org repo-hygiene gate keys on this filename; the lockfile
# carries multi-platform hashes for the pinned provider build.

terraform {

  required_version = "= 1.15.1"

  required_providers {

    aws = {
      source  = "hashicorp/aws"
      version = "= 6.47.0"
    }

  }

}
