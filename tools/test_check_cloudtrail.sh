#!/usr/bin/env bash
# Proves tools/event_selectors.jq against the trail shapes that matter, including the two that
# would otherwise pass while recording nothing the alerts need. Runs offline in `make ci`.

set -uo pipefail

tools_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sources='["ec2.amazonaws.com", "iam.amazonaws.com"]'
failed=0

expect() {
  local fixture="$1" want="$2" got
  got="$(jq -r --argjson sources "${sources}" -f "${tools_dir}/event_selectors.jq" \
    "${tools_dir}/fixtures/event-selectors/${fixture}")"
  if [ "${got}" != "${want}" ]; then
    printf 'FAIL %-38s expected %-5s got %s\n' "${fixture}" "${want}" "${got}" >&2
    failed=1
  else
    printf 'ok   %-38s %s\n' "${fixture}" "${got}"
  fi
}

expect basic-all.json true
expect basic-readonly.json false
expect advanced-management.json true
expect advanced-readonly-true.json false
expect advanced-excludes-both-sources.json false
expect advanced-only-ec2.json false
expect advanced-split-sources.json true

if [ "${failed}" -ne 0 ]; then
  echo "event_selectors.jq does not classify every trail shape correctly" >&2
  exit 1
fi
echo "check_cloudtrail: OK — every trail shape classified correctly"
