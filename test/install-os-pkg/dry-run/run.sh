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
INSTALL_SH="$SCRIPT_DIR/../../../src/install-os-pkg/script/install.sh"
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
# Helpers
# ---------------------------------------------------------------------------
_extract_packages() {
    # From run output, extract the package list on the [dry-run] packages line.
    # Prints one package per line, sorted.
    local output="$1"
    local line
    line=$(printf '%s\n' "$output" | grep '\[dry-run\] packages' || true)
    if [[ -n "$line" ]]; then
        printf '%s\n' "$line" | sed 's/.*): //' | tr ' ' '\n' | sort
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
    manifest="$case_dir/manifest.txt"
    expected_file="$case_dir/${PLATFORM_ID}.expected"

    if [[ ! -f "$manifest" ]]; then
        echo "WARN  $test_name: manifest.txt missing — skipping"
        (( skip++ )) || true
        continue
    fi

    if [[ ! -f "$expected_file" ]]; then
        echo "SKIP  $test_name"
        (( skip++ )) || true
        continue
    fi

    # Run in a subshell so failures are caught without killing the runner.
    output=$(bash "$INSTALL_SH" --manifest "$manifest" --dry_run --no_update 2>&1) || {
        echo "FAIL  $test_name (script exited non-zero)"
        echo "--- output ---"
        printf '%s\n' "$output"
        echo "--------------"
        (( fail++ )) || true
        continue
    }

    actual=$(_extract_packages "$output")
    expected=$(sort "$expected_file")

    if [[ "$actual" == "$expected" ]]; then
        echo "PASS  $test_name"
        (( pass++ )) || true
    else
        echo "FAIL  $test_name"
        echo "  expected : $(printf '%s\n' "$expected" | tr '\n' ' ')"
        echo "  actual   : $(printf '%s\n' "$actual"   | tr '\n' ' ')"
        (( fail++ )) || true
    fi
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Platform $PLATFORM_ID — $pass passed, $skip skipped, $fail failed"
[[ $fail -eq 0 ]]
