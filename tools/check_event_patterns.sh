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
# Which roles are exempt is deployment data: the caller names real roles the exemption must cover,
# and each replaces EXEMPT_ROLE in the fixtures. They are never derived from the pattern, which
# would let a misspelt pattern prove itself. A plan that exempts roles without a named role, or
# names roles without exempting any, fails; one that exempts nobody skips the fixtures that depend
# on an exemption. Needs events:TestEventPattern.

set -euo pipefail

plan_file="${1:?usage: check_event_patterns.sh <saved terraform plan file> [exempt role ...]}"
shift
exempt_roles=("$@")
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

  exempting="$(printf '%s' "${pattern}" | jq '.detail | has("$or")')"
  if [ "${key}" = "security-group" ] && [ "${exempting}" = "true" ] && [ "${#exempt_roles[@]}" -eq 0 ]; then
    echo "::error::${name} exempts roles, but no role it must exempt was named; pass at least one." >&2
    failed=1
    continue
  fi
  if [ "${key}" = "security-group" ] && [ "${exempting}" = "false" ] && [ "${#exempt_roles[@]}" -gt 0 ]; then
    echo "::error::Roles to exempt were named, but ${name} exempts nobody." >&2
    failed=1
    continue
  fi

  for fixture in "${fixture_dir}"/*.json; do
    case "$(basename "${fixture}")" in
      match-*) expected=true ;;
      nomatch-*) expected=false ;;
      *) echo "::error::${fixture} must be named match-*.json or nomatch-*.json." >&2; failed=1; continue ;;
    esac

    roles=("")
    if grep -q EXEMPT_ROLE "${fixture}"; then
      if [ "${#exempt_roles[@]}" -gt 0 ]; then
        roles=("${exempt_roles[@]}")
      elif [ "${key}" = "security-group" ]; then
        printf 'skip %-28s %-42s no role is exempt in this deployment\n' "${name}" "$(basename "${fixture}")"
        continue
      else
        # The IAM fixture proves a pipeline role is NOT exempt from IAM; any role name does.
        roles=("example-pipeline-role")
      fi
    fi

    for role in "${roles[@]}"; do
      actual="$(aws events test-event-pattern --region "${region}" \
        --event-pattern "${pattern}" \
        --event "$(sed "s/EXEMPT_ROLE/${role}/g" "${fixture}")" \
        --query Result --output text)"
      actual="$(printf '%s' "${actual}" | tr '[:upper:]' '[:lower:]')"
      checked=$((checked + 1))

      if [ "${actual}" != "${expected}" ]; then
        printf '::error::%s against %s %s: expected %s, EventBridge said %s\n' \
          "${name}" "$(basename "${fixture}")" "${role}" "${expected}" "${actual}" >&2
        failed=1
      else
        printf 'ok   %-28s %-42s %s%s\n' "${name}" "$(basename "${fixture}")" "${actual}" "${role:+ ${role}}"
      fi
    done
  done
done < <(printf '%s' "${planned}" | jq -c '.[]')

if [ "${failed}" -ne 0 ]; then
  echo "::error::Planned event patterns do not match what the fixtures require." >&2
  exit 1
fi

printf 'check_event_patterns: OK — %d checks matched as required\n' "${checked}"
