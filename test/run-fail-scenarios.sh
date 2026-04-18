#!/usr/bin/env bash
# Run "expected-to-fail" scenarios for the given feature.
# Usage: bash run-fail-scenarios.sh <feature>
#
# Sources test/<feature>/fail_scenarios.sh; each call to fail_scenario() runs
# the feature's install.bash inside a container and expects a non-zero
# exit.  Reports pass/fail counts and exits non-zero if any scenario exits zero.
#
# DSL (inside fail_scenarios.sh):
#   fail_scenario "label" [--network none] [--setup-cmd <cmd>] [KEY=VALUE ...]
#
# --network none: blocks all networking inside the test container.  The runner
#   pre-builds a base image with the feature's dependencies so apt-get is not
#   needed at test time.
# --setup-cmd <cmd>: runs additional shell commands inside the container before
#   invoking the feature install script. Useful for creating preconditions such
#   as an already-installed package.
set -euo pipefail

FEATURE="${1:?Usage: run-fail-scenarios.sh <feature>}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCENARIOS_FILE="${REPO_ROOT}/test/${FEATURE}/fail_scenarios.sh"
INSTALL_SCRIPT="src/${FEATURE}/install.bash"
DEPS_FILE="${REPO_ROOT}/src/${FEATURE}/dependencies/base.yaml"

if [[ ! -f "$SCENARIOS_FILE" ]]; then
  echo "ℹ️ No fail_scenarios.sh found for '${FEATURE}' — skipping."
  exit 0
fi

_pass=0
_fail=0
_errors=()
_BASE_IMAGE=""

_require_base_image() {
  [[ -n "$_BASE_IMAGE" ]] && return
  local pkgs="bash curl ca-certificates"
  if [[ -f "$DEPS_FILE" ]]; then
    # Extract package names from the top-level 'packages:' YAML list only.
    # Other keys (e.g. 'apk:') are skipped — they're distro-specific and not
    # needed for the Ubuntu base image used by fail scenarios.
    local _yaml_pkgs
    _yaml_pkgs="$(awk '/^packages:/{found=1;next} found && /^  - /{sub(/^  - /,""); print; next} found && /^[^[:space:]]/{found=0}' "$DEPS_FILE" | tr '\n' ' ' | xargs)"
    [[ -n "$_yaml_pkgs" ]] && pkgs="$_yaml_pkgs"
  fi
  _BASE_IMAGE="fail-test-base-${FEATURE}"
  echo "ℹ️ Building base image '${_BASE_IMAGE}' (packages: ${pkgs})..."
  docker build -q -t "$_BASE_IMAGE" - << DOCKERFILE
FROM ubuntu:latest
RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends ${pkgs} \
 && rm -rf /var/lib/apt/lists/*
DOCKERFILE
}

fail_scenario() {
  local label="$1"
  shift
  local -a net_args=()
  local -a env_args=()
  local use_base=false
  local setup_cmd=""
  local ready_marker="__FAIL_SCENARIO_INSTALL_STARTED__"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --network)
        net_args=(--network "$2")
        use_base=true
        shift 2
        ;;
      --setup-cmd)
        setup_cmd="$2"
        shift 2
        ;;
      *=*)
        env_args+=(-e "$1")
        shift
        ;;
      *) shift ;;
    esac
  done

  local image="ubuntu:latest"
  local pre_cmd="apt-get update -qq && apt-get install -y --no-install-recommends bash curl ca-certificates >/dev/null 2>&1 && "
  if [[ "$use_base" == true ]]; then
    _require_base_image
    image="$_BASE_IMAGE"
    pre_cmd=""
  fi

  echo ""
  echo "▶ Fail scenario: ${label}"
  local rc=0
  local output=""
  output="$({ docker run --rm \
    "${net_args[@]+"${net_args[@]}"}" \
    "${env_args[@]+"${env_args[@]}"}" \
    -v "${REPO_ROOT}:/repo" \
    "$image" \
    bash -c "set -e; ${pre_cmd}${setup_cmd:+${setup_cmd} && }printf '%s\n' '${ready_marker}' >&2; exec bash /repo/${INSTALL_SCRIPT}"; } 2>&1)" ||
    rc=$?

  printf '%s\n' "$output"

  if [[ $rc -ne 0 && "$output" == *"${ready_marker}"* ]]; then
    echo "✅ PASS: '${label}' exited ${rc} (non-zero as expected)"
    ((_pass++)) || true
  else
    if [[ $rc -eq 0 ]]; then
      echo "❌ FAIL: '${label}' exited 0 (expected non-zero)"
    else
      echo "❌ FAIL: '${label}' failed before the install script ran (exit ${rc})"
    fi
    _errors+=("$label")
    ((_fail++)) || true
  fi
}

# Source the scenarios file — each fail_scenario() call runs and records result
# shellcheck source=/dev/null
source "$SCENARIOS_FILE"

echo ""
echo "Fail scenarios: ${_pass} passed, ${_fail} failed."
if [[ "${#_errors[@]}" -gt 0 ]]; then
  echo "Failing scenarios:"
  for e in "${_errors[@]}"; do
    printf '  • %s\n' "$e"
  done
  exit 1
fi
