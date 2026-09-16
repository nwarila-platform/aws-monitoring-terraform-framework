#!/usr/bin/env bash
# Fail unless a logging CloudTrail trail delivers this region's write management events, global
# service events included. EventBridge receives "AWS API Call via CloudTrail" events only while
# such a trail exists (EventBridge User Guide, "AWS service events delivered via AWS CloudTrail"),
# so without one every rule this framework deploys is green in Terraform and silent in practice.
# IAM calls are global service events recorded as occurring in us-east-1, which is why the trail
# must include them.
#
# Read-only: describe-trails, get-trail-status, get-event-selectors. Needs jq and the AWS CLI.

set -euo pipefail

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
  echo "::error::No trail covers ${region} with global service events included; EventBridge will receive no CloudTrail events." >&2
  exit 1
fi

covering=""
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
done <<< "${candidates}"

if [ -z "${covering}" ]; then
  echo "::error::A trail covers ${region} but none is logging write management events; EventBridge will receive no CloudTrail events." >&2
  exit 1
fi
