#!/usr/bin/env bash
# Decide whether this account's CloudTrail configuration can carry the alerts, in one of two
# modes. EventBridge receives "AWS API Call via CloudTrail" events only while a logging trail
# exists (EventBridge User Guide, "AWS service events delivered via AWS CloudTrail"), so without
# one every rule this framework deploys is green in Terraform and silent in practice. IAM calls
# are global service events recorded as occurring in us-east-1, which is why the trail must
# include them.
#
#   check_cloudtrail.sh                 a covering trail MUST already exist (the default, and
#                                       what runs after an apply)
#   check_cloudtrail.sh --plan <file>   the saved plan is inspected: if it creates a trail, no
#                                       OTHER covering trail may exist, because AWS gives each
#                                       account one free copy of its management events and bills
#                                       every copy after it. If it creates none, the default rule
#                                       applies.
#
# Read-only: describe-trails, get-trail-status, get-event-selectors. Needs jq and the AWS CLI.

set -euo pipefail

plan_file=""
if [ "${1:-}" = "--plan" ]; then
  plan_file="${2:?--plan needs the path to a saved plan file}"
fi

region="${AWS_REGION:?AWS_REGION must name the region the rules deploy into}"
tools_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The CloudTrail eventSource values the deployed alerts depend on.
alerted_sources='["ec2.amazonaws.com", "iam.amazonaws.com"]' 

# A multi-region trail covers every region; a single-region trail covers only its home region.
# Organization trails owned by the management account are listed here too.
candidates="$(aws cloudtrail describe-trails --include-shadow-trails --region "${region}" \
  --output json \
  | jq -r --arg region "${region}" '
      .trailList[]
      | select(.IsMultiRegionTrail or .HomeRegion == $region)
      | select(.IncludeGlobalServiceEvents)
      | .TrailARN')"

if [ -z "${candidates}" ]; then
  if [ -n "${plan_file}" ]; then
    # An account with no trail is exactly the account this framework offers to create one for;
    # whether it does is decided below, from the plan.
    candidates=""
  else
    echo "::error::No trail covers ${region} with global service events included; EventBridge will receive no CloudTrail events." >&2
    exit 1
  fi
fi

covering=""
covering_names=""
while read -r trail; do
  logging="$(aws cloudtrail get-trail-status --name "${trail}" --region "${region}" \
    --query IsLogging --output text)"
  if [ "${logging}" != "True" ]; then
    echo "trail ${trail} is not logging"
    continue
  fi

  # Basic selectors say so directly; advanced selectors say it as a Management event category.
  # Either shape must admit write management events for BOTH alerted services, or the rules see
  # nothing. An advanced selector is only proof if it also leaves writes in (readOnly true records
  # reads only) and does not filter the service out: a management selector may narrow by
  # eventSource, and a trail that excludes ec2 or iam passes a category-only test while
  # delivering neither alert.
  # Both alerted services must have their write management events recorded, or the rules see
  # nothing. The selector semantics live in event_selectors.jq so that the fixture test proves
  # the same program this gate runs.
  writes="$(aws cloudtrail get-event-selectors --trail-name "${trail}" --region "${region}" \
    --output json \
    | jq -r --argjson sources "${alerted_sources}" -f "${tools_dir}/event_selectors.jq")"

  if [ "${writes}" != "true" ]; then
    echo "trail ${trail} is logging but records no write management events"
    continue
  fi

  echo "trail ${trail} is logging write management events for ${region}"
  covering="${trail}"
  covering_names="${covering_names}${covering_names:+$'\n'}${trail##*trail/}"
done <<< "${candidates}"


# What the plan intends, if a plan was given. An empty value means this deployment does not
# manage a trail, so the account must already have one.
planned_trail=""
if [ -n "${plan_file}" ]; then
  planned_trail="$(terraform -chdir="$(dirname "${plan_file}")" show -json "$(basename "${plan_file}")" \
    | jq -r '[ .planned_values.root_module.resources[]?
               | select(.type == "aws_cloudtrail")
               | .values.name ] | first // ""')"
fi

if [ -n "${planned_trail}" ]; then
  # Ours is allowed to be here already; anyone else's means a second copy of every management
  # event, billed.
  others="$(printf '%s\n' "${covering_names}" | grep -v "^${planned_trail}$" || true)"
  if [ -n "${others}" ]; then
    printf '::error::This deploy would create trail %s while these already cover %s: %s. ' \
      "${planned_trail}" "${region}" "$(printf '%s' "${others}" | tr '\n' ' ')" >&2
    printf 'A second trail bills every management event twice; set manage_trail = false.\n' >&2
    exit 1
  fi
  echo "no other trail covers ${region}; this deploy will create ${planned_trail}"
  exit 0
fi

if [ -z "${covering}" ]; then
  echo "::error::A trail covers ${region} but none is logging write management events; EventBridge will receive no CloudTrail events." >&2
  exit 1
fi
