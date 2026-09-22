#!/usr/bin/env bash
# Decide whether this account's CloudTrail configuration can carry the alerts. EventBridge
# receives "AWS API Call via CloudTrail" events only while a logging trail exists (EventBridge
# User Guide, "AWS service events delivered via AWS CloudTrail"), so without one every rule this
# framework deploys is green in Terraform and silent in practice.
#
#   check_cloudtrail.sh                 a trail must already log this region's write management
#                                       events, global service events included. Runs after apply.
#   check_cloudtrail.sh --plan <file>   if the saved plan CREATES a trail, the account must have
#                                       no trail at all, in any region: AWS gives one free copy
#                                       of management events per account and bills every copy
#                                       after it. If the plan creates none, the default rule
#                                       applies.
#
# Read-only: list-trails, describe-trails, get-trail-status, get-event-selectors.

set -euo pipefail

region="${AWS_REGION:?AWS_REGION must name the region the rules deploy into}"
tools_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "${1:-}" = "--plan" ]; then
  plan_file="${2:?--plan needs the path to a saved plan file}"
  creates_trail="$(terraform -chdir="$(dirname "${plan_file}")" show -json "$(basename "${plan_file}")" \
    | jq '[ .resource_changes[]? | select(.type == "aws_cloudtrail") | .change.actions[] ]
          | index("create") != null')"

  if [ "${creates_trail}" = "true" ]; then
    # Any existing trail may overlap the new one's management events, and one with the same name
    # would collide, so the only safe state to create into is an account with none.
    existing="$(aws cloudtrail list-trails --region "${region}" --query 'Trails[].TrailARN' --output text)"
    if [ -n "${existing}" ] && [ "${existing}" != "None" ]; then
      echo "::error::This deploy would create a trail, but the account already has: ${existing}. A second trail bills management events twice; set manage_trail = false." >&2
      exit 1
    fi
    echo "the account has no trail; this deploy creates one"
    exit 0
  fi
fi

# Covering means: logging, recording this region (multi-region or homed here), including global
# service events, and recording write management events.
candidates="$(aws cloudtrail describe-trails --include-shadow-trails --region "${region}" \
  --output json \
  | jq -r --arg region "${region}" '
      .trailList[]
      | select(.IsMultiRegionTrail or .HomeRegion == $region)
      | select(.IncludeGlobalServiceEvents)
      | .TrailARN')"

covering=""
while read -r trail; do
  [ -n "${trail}" ] || continue

  logging="$(aws cloudtrail get-trail-status --name "${trail}" --region "${region}" \
    --query IsLogging --output text)"
  if [ "${logging}" != "True" ]; then
    echo "trail ${trail} is not logging"
    continue
  fi

  writes="$(aws cloudtrail get-event-selectors --trail-name "${trail}" --region "${region}" \
    --output json | jq -r -f "${tools_dir}/event_selectors.jq")"
  if [ "${writes}" != "true" ]; then
    echo "trail ${trail} is logging but records no write management events"
    continue
  fi

  echo "trail ${trail} is logging write management events for ${region}"
  covering="${trail}"
done <<< "${candidates}"

if [ -z "${covering}" ]; then
  echo "::error::No logging trail records ${region}'s write management events with global service events included; EventBridge will receive no CloudTrail events." >&2
  exit 1
fi
