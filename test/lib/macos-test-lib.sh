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

# Remove a named block (identified by marker) from a file, in-place.
# No-op when the file does not exist or contains no block.
# Usage: block_cleanup "<marker>" "<file>"
block_cleanup() {
  local marker="$1" f="$2"
  [[ -f "$f" ]] || return 0
  local bm="# >>> ${marker} >>>" em="# <<< ${marker} <<<"
  local tmp
  tmp="$(mktemp)"
  awk -v bm="$bm" -v em="$em" '
    $0 == bm { skip=1; next }
    $0 == em { skip=0; next }
    !skip    { print }
  ' "$f" > "$tmp" && mv "$tmp" "$f"
  local rc=$?
  [[ $rc -ne 0 ]] && rm -f "$tmp"
  return $rc
}

# Remove a named block from every standard user init file in $HOME.
# Usage: block_cleanup_all "<marker>"
block_cleanup_all() {
  local marker="$1"
  local f
  for f in "${HOME}/.bash_profile" "${HOME}/.bash_login" "${HOME}/.profile" \
    "${HOME}/.bashrc" "${HOME}/.zprofile" "${HOME}/.zshenv" "${HOME}/.zshrc"; do
    block_cleanup "$marker" "$f"
  done
}

# Remove the install-homebrew shellenv block from a file, in-place.
# No-op when the file does not exist or contains no block.
shellenv_block_cleanup() {
  block_cleanup "brew shellenv (install-homebrew)" "$1"
}
