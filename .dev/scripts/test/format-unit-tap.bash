#!/usr/bin/env bash
# Emit unambiguous TAP for run-unit.sh while preserving exact BATS test names.

set -euo pipefail
trap '' INT

# BATS reports a test's name separately in the extended `begin` event. Its
# stock TAP formatter concatenates that raw name, `# skip`, and the raw reason,
# making those fields impossible to recover unambiguously afterward.
declare -A _devfeats_test_names=()

bats_tap_stream_plan() { printf '1..%d\n' "$1"; }
bats_tap_stream_suite() { :; }
bats_tap_stream_begin() { _devfeats_test_names["$1"]="$2"; }

_devfeats_emit_name() {
  local _index="$1" _fallback="$2"
  printf '# devfeats-test-name %d %s\n' \
    "$_index" "${_devfeats_test_names[$_index]:-$_fallback}"
}

bats_tap_stream_ok() {
  _devfeats_emit_name "$1" "$2"
  printf 'ok %d\n' "$1"
}

bats_tap_stream_not_ok() {
  _devfeats_emit_name "$1" "$2"
  printf 'not ok %d\n' "$1"
}

bats_tap_stream_skipped() {
  local _index="$1" _parsed_name="$2" _original
  _original="${_devfeats_test_names[$_index]:-$_parsed_name}"
  _devfeats_emit_name "$_index" "$_parsed_name"

  # formatter.bash finds the last raw ` # skip` token. The exact begin name
  # distinguishes an appended directive from the same text in a passing name
  # or an earlier occurrence in a skip reason.
  if [[ "$_parsed_name" == "$_original" || "$_parsed_name" == "$_original # skip"* ]]; then
    printf 'ok %d # SKIP\n' "$_index"
  elif [[ "$_original" == "$_parsed_name # skip"* ]]; then
    printf 'ok %d\n' "$_index"
  else
    printf 'not ok %d\n' "$_index"
    printf '    Formatter could not correlate the result with its begin event.\n'
  fi
}

bats_tap_stream_comment() { printf '    %s\n' "$1"; }
bats_tap_stream_unknown() { printf '%s\n' "$1"; }

# shellcheck source=test/lib/bats/bats-core/lib/bats-core/formatter.bash
source "$BATS_ROOT/$BATS_LIBDIR/bats-core/formatter.bash"
bats_parse_internal_extended_tap
