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
  # Either shape must admit write management events, or the rules see nothing.
  writes="$(aws cloudtrail get-event-selectors --trail-name "${trail}" --region "${region}" \
    --output json \
    | jq -r '
        (
          [.EventSelectors[]? | select(.IncludeManagementEvents and .ReadWriteType != "ReadOnly")]
          + [.AdvancedEventSelectors[]? | select(any(.FieldSelectors[]; .Field == "eventCategory" and (.Equals // []) == ["Management"]))]
        ) | length > 0')"
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
