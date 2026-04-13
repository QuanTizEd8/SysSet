#!/usr/bin/env bash
# assert.sh — Shared assertion helpers for all test/ scenarios.
#
# API-compatible with dev-container-features-test-lib:
#   check "label" <cmd> [args...]                   — passes if <cmd> exits 0
#   fail_check "label" <cmd> [args...]              — passes if <cmd> exits non-zero
#   checkMultiple "label" <min> "cmd1" ["cmd2"...]  — passes if ≥ <min> cmds exit 0
#   reportResults                                   — print summary; exit 1 if any failed
#
# macOS block-cleanup helpers:
#   block_cleanup "<marker>" "<file>"   — remove a named block from a file in-place
#   block_cleanup_all "<marker>"        — remove from all standard shell init files
#   shellenv_block_cleanup "<file>"     — remove install-homebrew shellenv block
#
# File server helpers (dist scenarios):
#   start_file_server <dir> <port>      — start python3 HTTP server in background
#   stop_file_server                    — stop the background server
#   wait_for_port <port> [<timeout_s>]  — block until TCP port is open

_TEST_PASS=0
_TEST_FAIL=0
_TEST_FAILURES=()

check() {
  local label="$1"
  shift
  local out rc=0
  out="$("$@" 2>&1)" || rc=$?
  if [[ $rc -eq 0 ]]; then
    printf '  ✅  PASS — %s\n' "$label"
    ((_TEST_PASS++)) || true
  else
    printf '  ❌  FAIL — %s (exit %d)\n' "$label" "$rc"
    [[ -n "$out" ]] && printf '         %s\n' "$out"
    _TEST_FAILURES+=("$label")
    ((_TEST_FAIL++)) || true
  fi
}

# Inverse of check: passes when <cmd> exits non-zero.
fail_check() {
  local label="$1"
  shift
  local out rc=0
  out="$("$@" 2>&1)" || rc=$?
  if [[ $rc -ne 0 ]]; then
    printf '  ✅  PASS (expected non-zero, exit %d) — %s\n' "$rc" "$label"
    ((_TEST_PASS++)) || true
  else
    printf '  ❌  FAIL (expected non-zero, got 0) — %s\n' "$label"
    [[ -n "$out" ]] && printf '         %s\n' "$out"
    _TEST_FAILURES+=("$label")
    ((_TEST_FAIL++)) || true
  fi
}

# Runs each remaining argument as a shell string via eval.
# Passes if at least <min_passed> of them exit 0.
# Usage: checkMultiple "label" <min_passed> "cmd1" ["cmd2" ...]
checkMultiple() {
  local label="$1" min_passed="$2"
  shift 2
  local passed=0 expr out rc
  printf '\n🔄 Testing (multiple) "%s"\n' "$label"
  while [[ $# -gt 0 ]]; do
    expr="$1"
    shift
    [[ -z "$expr" ]] && continue
    rc=0
    out="$(eval "$expr" 2>&1)" || rc=$?
    if [[ $rc -eq 0 ]]; then ((passed++)) || true; fi
  done
  if ((passed >= min_passed)); then
    printf '  ✅  PASS — %s (%d/%d)\n' "$label" "$passed" "$min_passed"
    ((_TEST_PASS++)) || true
  else
    printf '  ❌  FAIL — %s (%d/%d required)\n' "$label" "$passed" "$min_passed"
    _TEST_FAILURES+=("$label")
    ((_TEST_FAIL++)) || true
  fi
}

reportResults() {
  echo ""
  echo "Results: ${_TEST_PASS} passed, ${_TEST_FAIL} failed."
  if [[ ${_TEST_FAIL} -gt 0 ]]; then
    echo "Failed checks:"
    for _f in "${_TEST_FAILURES[@]}"; do
      printf '  — %s\n' "$_f"
    done
    exit 1
  fi
}

# ── macOS block-cleanup helpers ───────────────────────────────────────────────

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

# ── File server helpers ───────────────────────────────────────────────────────

_FILE_SERVER_PID=""

# start_file_server <dir> <port>
# Starts 'python3 -m http.server <port>' in <dir> in the background.
# Stores the PID in _FILE_SERVER_PID. Call stop_file_server in a trap.
start_file_server() {
  local _dir="$1"
  local _port="$2"
  python3 -m http.server "$_port" --directory "$_dir" \
    > /tmp/file-server-"$_port".log 2>&1 &
  _FILE_SERVER_PID=$!
  wait_for_port "$_port" 10
}

# stop_file_server
# Kills the background file server started by start_file_server.
stop_file_server() {
  if [[ -n "$_FILE_SERVER_PID" ]]; then
    kill "$_FILE_SERVER_PID" 2> /dev/null || true
    _FILE_SERVER_PID=""
  fi
}

# wait_for_port <port> [<timeout_s>]
# Blocks until 127.0.0.1:<port> accepts TCP connections.
wait_for_port() {
  local _port="$1"
  local _timeout="${2:-10}"
  local _elapsed=0
  while ! bash -c "echo > /dev/tcp/127.0.0.1/${_port}" 2> /dev/null; do
    sleep 0.2
    _elapsed=$(echo "$_elapsed + 0.2" | bc)
    if (($(echo "$_elapsed >= $_timeout" | bc -l))); then
      echo "⛔ Timed out waiting for port ${_port}" >&2
      return 1
    fi
  done
}
