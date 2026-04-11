#!/usr/bin/env bash
# Run macOS-native test scenarios for a given feature.
#
# Usage:
#   bash test/run-macos.sh <feature> [--filter <scenario_name>]
#
# Discovers and runs every test/<feature>/macos/*.sh script in alphabetical
# order.  Each scenario script receives the repository root as its first
# positional argument.
#
# Exit code: 0 if all scenarios pass, 1 if any fail.
set -euo pipefail

FEATURE="${1:?Usage: run-macos.sh <feature> [--filter <scenario>]}"
shift

FILTER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --filter)
      shift
      FILTER="${1:?--filter requires a value}"
      shift
      ;;
    *)
      echo "⛔ Unknown option: '$1'" >&2
      exit 1
      ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCENARIOS_DIR="${REPO_ROOT}/test/${FEATURE}/macos"

if [[ ! -d "$SCENARIOS_DIR" ]]; then
  echo "ℹ️  No macOS scenarios for '${FEATURE}' (${SCENARIOS_DIR} does not exist) — skipping."
  exit 0
fi

echo "ℹ️  Syncing _lib/ copies from lib/ before running macOS scenarios."
bash "${REPO_ROOT}/sync-lib.sh"

_pass=0
_fail=0
_errors=()

_sep() {
  printf '%.0s━' {1..60}
  echo
}

for scenario in "${SCENARIOS_DIR}"/*.sh; do
  [[ -f "$scenario" ]] || continue
  name="$(basename "$scenario" .sh)"
  [[ -n "$FILTER" && "$name" != "$FILTER" ]] && continue

  echo ""
  _sep
  echo "▶  ${FEATURE} / macOS / ${name}"
  _sep
  if bash "$scenario" "$REPO_ROOT"; then
    echo "✅ PASS: ${name}"
    ((_pass++)) || true
  else
    echo "❌ FAIL: ${name}"
    _errors+=("$name")
    ((_fail++)) || true
  fi
done

echo ""
printf '%.0s═' {1..60}
echo
echo "macOS scenarios for '${FEATURE}': ${_pass} passed, ${_fail} failed."
printf '%.0s═' {1..60}
echo

if [[ ${_fail} -gt 0 ]]; then
  echo "Failing scenarios:"
  for e in "${_errors[@]}"; do
    printf '  — %s\n' "$e"
  done
  exit 1
fi
