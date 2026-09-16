#!/usr/bin/env bash
# Prove every planned event pattern against AWS's own matcher before the plan is applied.
#
# The mocked test suite can assert what a pattern CONTAINS; only EventBridge can say what it
# MATCHES. The pipeline exemption is the reason this exists: excluding a role by a nested field
# would also have excluded every event that carries no assumed-role identity, which is a silent
# loss of exactly the alerts that matter most. Each fixture under fixtures/events/<rule key>/ is
# named for the answer it must get, and a wrong answer fails the deploy before anything changes.
#
# Reads the saved plan rather than the deployed rules, so a broken pattern never reaches AWS.
# Needs events:TestEventPattern.

set -euo pipefail

plan_file="${1:?usage: check_event_patterns.sh <saved terraform plan file>}"
region="${AWS_REGION:?AWS_REGION must name the region the rules deploy into}"
tools_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
terraform_dir="$(dirname "${plan_file}")"

# name -> pattern, straight from the plan Terraform is about to apply.
planned="$(terraform -chdir="${terraform_dir}" show -json "$(basename "${plan_file}")" \
  | jq -c '[ .planned_values.root_module.resources[]
             | select(.type == "aws_cloudwatch_event_rule")
             | { name: .values.name, pattern: .values.event_pattern } ]')"

if [ "$(printf '%s' "${planned}" | jq 'length')" -eq 0 ]; then
  echo "::error::The plan contains no EventBridge rules; there is nothing to prove." >&2
  exit 1
fi

failed=0
checked=0

while read -r rule; do
  name="$(printf '%s' "${rule}" | jq -r .name)"
  pattern="$(printf '%s' "${rule}" | jq -r .pattern)"
  key="${name#security-change-alerts-}"
  fixture_dir="${tools_dir}/fixtures/events/${key}"

  if [ ! -d "${fixture_dir}" ]; then
    echo "::error::Rule ${name} has no fixtures at fixtures/events/${key}; every alert must be proven." >&2
    failed=1
    continue
  fi

  for fixture in "${fixture_dir}"/*.json; do
    case "$(basename "${fixture}")" in
      match-*) expected=true ;;
      nomatch-*) expected=false ;;
      *) echo "::error::${fixture} must be named match-*.json or nomatch-*.json." >&2; failed=1; continue ;;
    esac

    actual="$(aws events test-event-pattern --region "${region}" \
      --event-pattern "${pattern}" \
      --event "$(cat "${fixture}")" \
      --query Result --output text)"
    actual="$(printf '%s' "${actual}" | tr '[:upper:]' '[:lower:]')"
    checked=$((checked + 1))

    if [ "${actual}" != "${expected}" ]; then
      printf '::error::%s against %s: expected %s, EventBridge said %s\n' \
        "${name}" "$(basename "${fixture}")" "${expected}" "${actual}" >&2
      failed=1
    else
      printf 'ok   %-28s %-42s %s\n' "${name}" "$(basename "${fixture}")" "${actual}"
    fi
  done
done < <(printf '%s' "${planned}" | jq -c '.[]')

if [ "${failed}" -ne 0 ]; then
  echo "::error::Planned event patterns do not match what the fixtures require." >&2
  exit 1
fi

printf 'check_event_patterns: OK — %d fixtures matched as required\n' "${checked}"
