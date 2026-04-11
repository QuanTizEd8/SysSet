#!/usr/bin/env bash
# macOS native test library.
#
# Drop-in API compatible with dev-container-features-test-lib:
#   check "label" <command> [args...]  — pass if command exits 0
#   reportResults                      — print summary; exit 1 if any check failed
#
# Additional:
#   fail_check "label" <command> [args...]  — pass if command exits non-zero
#   shellenv_block_cleanup <file>           — remove install-homebrew shellenv block in-place

_MACOS_TEST_PASS=0
_MACOS_TEST_FAIL=0
_MACOS_TEST_FAILURES=()

check() {
  local label="$1"
  shift
  local out rc=0
  out="$("$@" 2>&1)" || rc=$?
  if [[ $rc -eq 0 ]]; then
    printf '  ✅  PASS — %s\n' "$label"
    ((_MACOS_TEST_PASS++)) || true
  else
    printf '  ❌  FAIL — %s (exit %d)\n' "$label" "$rc"
    [[ -n "$out" ]] && printf '         %s\n' "$out"
    _MACOS_TEST_FAILURES+=("$label")
    ((_MACOS_TEST_FAIL++)) || true
  fi
}

# Inverse of check: passes when the command exits non-zero.
fail_check() {
  local label="$1"
  shift
  local out rc=0
  out="$("$@" 2>&1)" || rc=$?
  if [[ $rc -ne 0 ]]; then
    printf '  ✅  PASS (expected failure, exit %d) — %s\n' "$rc" "$label"
    ((_MACOS_TEST_PASS++)) || true
  else
    printf '  ❌  FAIL (expected non-zero exit, got 0) — %s\n' "$label"
    [[ -n "$out" ]] && printf '         %s\n' "$out"
    _MACOS_TEST_FAILURES+=("$label")
    ((_MACOS_TEST_FAIL++)) || true
  fi
}

reportResults() {
  echo ""
  echo "Results: ${_MACOS_TEST_PASS} passed, ${_MACOS_TEST_FAIL} failed."
  if [[ ${_MACOS_TEST_FAIL} -gt 0 ]]; then
    echo "Failed checks:"
    for f in "${_MACOS_TEST_FAILURES[@]}"; do
      printf '  — %s\n' "$f"
    done
    exit 1
  fi
}

# Remove the install-homebrew shellenv block from a file, in-place.
# No-op when the file does not exist or contains no block.
shellenv_block_cleanup() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  local tmp
  tmp="$(mktemp)"
  awk '
    /^# >>> brew shellenv \(install-homebrew\) >>>$/ { skip=1; next }
    /^# <<< brew shellenv \(install-homebrew\) <<<$/ { skip=0; next }
    !skip { print }
  ' "$f" > "$tmp" && mv "$tmp" "$f" || rm -f "$tmp"
}
