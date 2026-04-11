#!/usr/bin/env bash
# test/run-unit.sh — local runner for lib/ unit tests.
#
# Usage:
#   bash test/run-unit.sh                       # run all modules
#   bash test/run-unit.sh --module os           # run test/unit/os.bats only
#   bash test/run-unit.sh --filter "platform"   # regex filter (--filter-tags)
#   bash test/run-unit.sh --jobs 1              # serial execution (default: auto)

set -euo pipefail

_REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
_BATS="${_REPO_ROOT}/test/unit/bats/bats-core/bin/bats"
_UNIT_DIR="${_REPO_ROOT}/test/unit"

# ── Argument parsing ─────────────────────────────────────────────────────────
_module=""
_filter=""
_jobs=0 # 0 = let bats decide (auto / num CPUs)

while [[ $# -gt 0 ]]; do
  case $1 in
    --module)
      shift
      _module="$1"
      shift
      ;;
    --filter)
      shift
      _filter="$1"
      shift
      ;;
    --jobs)
      shift
      _jobs="$1"
      shift
      ;;
    --help | -h)
      cat << 'HELP'
Usage: bash test/run-unit.sh [--module <name>] [--filter <regex>] [--jobs <n>]

  --module <name>    Run only test/unit/<name>.bats  (e.g. os, shell, ospkg)
  --filter <regex>   Pass --filter to bats (matches test names by regex)
  --jobs <n>         Parallel job count (default: auto)
HELP
      exit 0
      ;;
    *)
      echo "⛔ Unknown option: '$1'" >&2
      exit 1
      ;;
  esac
done

# ── Pre-flight checks ────────────────────────────────────────────────────────
if [[ ! -x "$_BATS" ]]; then
  echo "⛔ bats not found at '${_BATS}'." >&2
  echo "   Run: git submodule update --init --recursive" >&2
  exit 1
fi

# Ensure generated _lib/ copies are up to date.
bash "${_REPO_ROOT}/sync-lib.sh"

# ── Build file list ──────────────────────────────────────────────────────────
declare -a _test_files=()
if [[ -n "$_module" ]]; then
  _target="${_UNIT_DIR}/${_module}.bats"
  if [[ ! -f "$_target" ]]; then
    echo "⛔ Module test not found: '${_target}'" >&2
    exit 1
  fi
  _test_files=("$_target")
else
  while IFS= read -r -d '' _f; do
    _test_files+=("$_f")
  done < <(find "$_UNIT_DIR" -maxdepth 1 -name '*.bats' -print0 | sort -z)
fi

if [[ ${#_test_files[@]} -eq 0 ]]; then
  echo "⚠️  No .bats files found in '${_UNIT_DIR}'." >&2
  exit 0
fi

# ── Run ──────────────────────────────────────────────────────────────────────
declare -a _bats_args=(--print-output-on-failure)

[[ "$_jobs" -gt 0 ]] && _bats_args+=(--jobs "$_jobs")
[[ -n "$_filter" ]] && _bats_args+=(--filter "$_filter")

exec "$_BATS" "${_bats_args[@]}" "${_test_files[@]}"
