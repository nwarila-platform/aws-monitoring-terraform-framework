# Variable declarations. Deployment environment and recipients first, then the deployment
# identity the runner supplies on the command line.

variable "environment" {
  description = <<-EOT
    Deployment environment tag value applied to managed AWS resources. Exactly one of dev, test,
    or prod (lowercase).
  EOT
  type        = string
  nullable    = false

  # A closed, case-exact lowercase set rather than a free-form string: the value lands verbatim in
  # the Environment tag on every managed resource, so accepting spelling or case variants ("Dev",
  # "PROD", "production") would fragment the estate's tag-based inventory and cost queries.
  validation {
    condition = contains(["dev", "test", "prod"], var.environment)
    error_message = join(" ", [
      "environment must be exactly one of \"dev\", \"test\", or \"prod\" (lowercase); the value",
      "is stamped verbatim onto every managed resource's Environment tag, so case and spelling",
      "variants are rejected.",
    ])
  }
}

variable "alert_emails" {
  description = <<-EOT
    Email addresses that receive every change alert. Each address becomes one email subscription
    on the alert topic; SNS then emails the address a confirmation link, and nothing is delivered
    until the recipient follows it. An empty list creates the topic and rules with no recipients,
    which is the bootstrap state before the first addresses are agreed.
  EOT
  type        = list(string)
  nullable    = false

  validation {
    condition = alltrue([
      for email in var.alert_emails : can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", email))
    ])
    error_message = "alert_emails entries must each be one address of the form local-part@domain.tld."
  }

  # A duplicate would be a duplicate resource key, which Terraform reports as an opaque for_each
  # error; naming the real mistake here is kinder.
  validation {
    condition     = length(distinct(var.alert_emails)) == length(var.alert_emails)
    error_message = "alert_emails must not list the same address twice."
  }

  # An empty list is the bootstrap state for dev and test. In prod it is a deployment that
  # applies green, reports success, and can never email anyone.
  validation {
    condition     = var.environment != "prod" || length(var.alert_emails) > 0
    error_message = "alert_emails must name at least one recipient when environment is \"prod\"."
  }
}

variable "exempt_pipeline_roles" {
  description = <<-EOT
    IAM role names whose security-group changes are not emailed, for automation that rewrites
    security groups on every run and would otherwise drown the changes a person needs to see. The
    exemption is narrow by construction: it applies to the security-group alert only, never to
    IAM, and an event carrying no assumed-role identity still alerts. The default exempts nobody.
  EOT
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for role in var.exempt_pipeline_roles : can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", role))
    ])
    error_message = "exempt_pipeline_roles entries must each be a bare IAM role name, not an ARN or a path."
  }

  validation {
    condition     = length(distinct(var.exempt_pipeline_roles)) == length(var.exempt_pipeline_roles)
    error_message = "exempt_pipeline_roles must not list the same role twice."
  }
}

variable "manage_trail" {
  description = <<-EOT
    Create the CloudTrail trail these alerts depend on. EventBridge receives no CloudTrail events
    at all unless a logging trail exists, so an account without one needs this set. It defaults
    to false because creating a trail is the costly mistake: AWS gives each account one free copy
    of its management events and bills every copy after it. Set it true only for an account with
    no trail; tools/check_cloudtrail.sh tells the two cases apart.
  EOT
  type        = bool
  default     = false
  nullable    = false
}

variable "repository" {
  description = "Path of the deploying repository, such as owner/name or group/subgroup/name, stamped as the Repository tag."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)+$", var.repository))
    error_message = "repository must be a path of two or more segments, such as owner/name or group/subgroup/name."
  }

  validation {
    condition     = length(var.repository) <= 256
    error_message = "repository must be at most 256 characters so its tag value fits the AWS tag-value limit."
  }
}

variable "repository_id" {
  description = "Numeric, rename-stable id the source host gives the repository or project — the anchor of the deployment identity, stamped as the RepositoryId tag."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]+$", var.repository_id))
    error_message = "repository_id must be the numeric, rename-stable repository or project id."
  }

  validation {
    condition     = length(var.repository_id) <= 256
    error_message = "repository_id must be at most 256 characters so its tag value fits the AWS tag-value limit."
  }
}

variable "commit_sha" {
  description = "Checked-out commit (git rev-parse HEAD after checkout, never a synthetic merge commit), stamped as the CommitSha tag."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.commit_sha))
    error_message = "commit_sha must be the lowercase 40-character checked-out commit SHA (git rev-parse HEAD after checkout)."
  }
}

variable "run_id" {
  description = "Numeric id of the pipeline run or build, stamped as the RunId tag. The run record holds actors, timestamps, and approvals; those stay in deployment evidence rather than in tags."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]+$", var.run_id))
    error_message = "run_id must be the numeric id of the pipeline run or build."
  }
}
