#!/usr/bin/env bash
# Manifest resolution test runner.
#
# For each test case under cases/ the script:
#   1. Runs script/install.sh --dry_run --no_update against the case manifest.
#   2. Parses the "[dry-run] packages" line from the output.
#   3. Compares the sorted actual package list to the sorted expected file.
#
# A case is SKIP-ped when no expected file exists for the current platform,
# which means "this combination is not relevant / intentionally untested".
# A case with an empty expected file asserts that 0 packages are resolved.
#
# Usage (in a container or as root):
#   bash run.sh
#
# The PLATFORM_ID env var can be set to override auto-detection (useful for
# local testing on macOS where /etc/os-release may not exist).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_SH="$SCRIPT_DIR/../../../src/install-os-pkg/scripts/install.sh"
CASES_DIR="$SCRIPT_DIR/cases"

# ---------------------------------------------------------------------------
# Platform detection
# ---------------------------------------------------------------------------
if [[ -z "${PLATFORM_ID:-}" ]]; then
  if [[ -f /etc/os-release ]]; then
    PLATFORM_ID=$(. /etc/os-release && printf '%s' "$ID")
  else
    echo "⛔ Cannot detect platform: /etc/os-release not found and PLATFORM_ID not set." >&2
    exit 1
  fi
fi
echo "▶  Platform: $PLATFORM_ID"
echo "▶  Install script: $INSTALL_SH"
echo ""

# ---------------------------------------------------------------------------
# Pre-install tools required by the YAML manifest parser (jq, yq).
# Installing once here avoids repeated downloads across test cases and
# prevents GitHub API rate-limit errors during local development.
# ---------------------------------------------------------------------------
LIB_DIR="$SCRIPT_DIR/../../../lib"
# shellcheck source=lib/os.sh
. "$LIB_DIR/os.sh"
# shellcheck source=lib/ospkg.sh
. "$LIB_DIR/ospkg.sh"
# shellcheck source=lib/net.sh
. "$LIB_DIR/net.sh"
ospkg::detect
if ! command -v jq > /dev/null 2>&1; then
  echo "▶  Installing jq (required by YAML parser)."
  ospkg::update --force >&2
  ospkg::install jq >&2
fi
if ! command -v yq > /dev/null 2>&1 || ! yq -o=json '.' /dev/null > /dev/null 2>&1; then
  echo "▶  Installing yq (required by YAML parser)."
  # shellcheck source=lib/github.sh
  . "$LIB_DIR/github.sh"
  # shellcheck source=lib/checksum.sh
  . "$LIB_DIR/checksum.sh"
  _ospkg_ensure_yq
  # Make yq available system-wide for subsequent test invocations.
  if [[ -n "${_OSPKG_YQ_BIN:-}" && "$_OSPKG_YQ_BIN" != "yq" ]]; then
    cp "$_OSPKG_YQ_BIN" /usr/local/bin/yq 2> /dev/null ||
      cp "$_OSPKG_YQ_BIN" /usr/bin/yq 2> /dev/null ||
      true
  fi
fi
echo ""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
_extract_packages() {
  # From run output, extract the package list on the [dry-run] packages line.
  # Prints one package per line, sorted.
  local output="$1"
  local line
  line=$(printf '%s\n' "$output" | grep '\[dry-run\] packages' || true)
  if [[ -n "$line" ]]; then
    printf '%s\n' "$line" | sed 's/.*packages: //' | tr ' ' '\n' | sort
  fi
  # If no packages line exists, prints nothing (empty → 0 packages expected).
}

# ---------------------------------------------------------------------------
# Run cases
# ---------------------------------------------------------------------------
pass=0
fail=0
skip=0

for case_dir in "$CASES_DIR"/*/; do
  test_name="$(basename "$case_dir")"
  manifest="$case_dir/manifest.yaml"
  expected_file="$case_dir/${PLATFORM_ID}.expected"

  if [[ ! -f "$manifest" ]]; then
    echo "WARN  $test_name: manifest.yaml missing — skipping"
    ((skip++)) || true
    continue
  fi

  if [[ ! -f "$expected_file" ]]; then
    echo "SKIP  $test_name"
    ((skip++)) || true
    continue
  fi

  # Run in a subshell so failures are caught without killing the runner.
  output=$(bash "$INSTALL_SH" --manifest "$manifest" --dry_run --no_update 2>&1) || {
    echo "FAIL  $test_name (script exited non-zero)"
    echo "--- output ---"
    printf '%s\n' "$output"
    echo "--------------"
    ((fail++)) || true
    continue
  }

  actual=$(_extract_packages "$output")
  expected=$(sort "$expected_file")

  case_pass=true

  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL  $test_name (package mismatch)"
    echo "  expected : $(printf '%s\n' "$expected" | tr '\n' ' ')"
    echo "  actual   : $(printf '%s\n' "$actual" | tr '\n' ' ')"
    case_pass=false
  fi

  # Optional: verify expected lines appear in the dry-run output.
  key_output_file="$case_dir/key_output.expected"
  if [[ -f "$key_output_file" ]]; then
    while IFS= read -r _kline || [[ -n "$_kline" ]]; do
      [[ -z "${_kline:-}" ]] && continue
      if ! printf '%s\n' "$output" | grep -qF "$_kline"; then
        echo "FAIL  $test_name (key output line missing: '$_kline')"
        case_pass=false
      fi
    done < "$key_output_file"
  fi

  # Optional: verify paths listed in no_files.expected were NOT created.
  no_files_file="$case_dir/no_files.expected"
  if [[ -f "$no_files_file" ]]; then
    while IFS= read -r _nfline || [[ -n "$_nfline" ]]; do
      [[ -z "${_nfline:-}" ]] && continue
      if [[ -e "$_nfline" ]]; then
        echo "FAIL  $test_name (file should not exist in dry-run: '$_nfline')"
        case_pass=false
      fi
    done < "$no_files_file"
  fi

  if [[ "$case_pass" == true ]]; then
    echo "PASS  $test_name"
    ((pass++)) || true
  else
    ((fail++)) || true
  fi
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Platform $PLATFORM_ID — $pass passed, $skip skipped, $fail failed"
[[ $fail -eq 0 ]]
