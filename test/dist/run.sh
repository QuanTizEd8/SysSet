#!/usr/bin/env bash
# run.sh — Runner for test/dist/ scenarios.
#
# Usage:
#   bash test/dist/run.sh [--suite <build|get|sysset|macos>] [--filter <name>]
#
# Discovers and runs scenario scripts under test/dist/scenarios/<suite>/*.sh.
# Each scenario is executed in a subshell; return code determines pass/fail.
#
# Exit code: 0 if all scenarios pass, 1 if any fail.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCENARIOS_BASE="${REPO_ROOT}/test/dist/scenarios"
SUITES=(build get sysset macos)

SUITE_FILTER=""
NAME_FILTER=""
BUILD=true
VERSION="v0.1.0-test"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --suite)
      shift
      SUITE_FILTER="${1:?--suite requires a value (build|get|sysset|macos)}"
      shift
      ;;
    --filter)
      shift
      NAME_FILTER="${1:?--filter requires a value}"
      shift
      ;;
    --version)
      shift
      VERSION="${1:?--version requires a value}"
      shift
      ;;
    --no-build)
      BUILD=false
      shift
      ;;
    --help | -h)
      cat << EOF
Usage: bash test/dist/run.sh [--suite <build|get|sysset|macos>] [--filter <name>] [--version <tag>] [--no-build]
EOF
      exit 0
      ;;
    *)
      echo "⛔ Unknown option: '$1'" >&2
      exit 1
      ;;
  esac
done

# ── Centralised build (skipped with --no-build) ───────────────────────────────
export SYSSET_BUILD_VERSION=""
if [[ "$BUILD" == true ]]; then
  echo "ℹ️  Building dist/ artifacts for tag '${VERSION}' ..." >&2
  bash "${REPO_ROOT}/build-artifacts.sh" "${VERSION}"
  export SYSSET_BUILD_VERSION="${VERSION}"
fi

_pass=0
_fail=0
_skip=0
_errors=()

_sep() {
  printf '%.0s─' {1..60}
  echo
}
_bold_sep() {
  printf '%.0s═' {1..60}
  echo
}

run_scenario() {
  local _suite="$1"
  local _script="$2"
  local _name
  _name="$(basename "$_script" .sh)"

  [[ -n "$NAME_FILTER" && "$_name" != "$NAME_FILTER" ]] && {
    ((_skip++)) || true
    return 0
  }

  echo ""
  _sep
  echo "▶  dist / ${_suite} / ${_name}"
  _sep
  if bash "$_script" "$REPO_ROOT"; then
    echo "✅ PASS: ${_suite}/${_name}"
    ((_pass++)) || true
  else
    echo "❌ FAIL: ${_suite}/${_name}"
    _errors+=("${_suite}/${_name}")
    ((_fail++)) || true
  fi
}

for suite in "${SUITES[@]}"; do
  [[ -n "$SUITE_FILTER" && "$suite" != "$SUITE_FILTER" ]] && continue
  suite_dir="${SCENARIOS_BASE}/${suite}"
  [[ -d "$suite_dir" ]] || continue

  for script in "${suite_dir}"/*.sh; do
    [[ -f "$script" ]] || continue
    run_scenario "$suite" "$script"
  done
done

echo ""
_bold_sep
echo "dist tests: ${_pass} passed, ${_fail} failed, ${_skip} skipped."
_bold_sep

if [[ ${_fail} -gt 0 ]]; then
  echo "Failing scenarios:"
  for e in "${_errors[@]}"; do
    printf '  — %s\n' "$e"
  done
  exit 1
fi
