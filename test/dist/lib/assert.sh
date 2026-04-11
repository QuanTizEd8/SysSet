#!/usr/bin/env bash
# assert.sh — Shared assertion helpers for test/dist/ scenarios.
#
# API-compatible with dev-container-features-test-lib and macos-test-lib.sh:
#   check "label" <cmd> [args...]       — passes if <cmd> exits 0
#   fail_check "label" <cmd> [args...]  — passes if <cmd> exits non-zero
#   reportResults                       — print summary; exit 1 if any failed
#
# Additional:
#   start_file_server <dir> <port>      — start python3 HTTP server; PID → _FILE_SERVER_PID
#   stop_file_server                    — stop the background server
#   wait_for_port <port> [<timeout_s>]  — block until TCP port is open

_ASSERT_PASS=0
_ASSERT_FAIL=0
_ASSERT_FAILURES=()

check() {
  local label="$1"
  shift
  local out rc=0
  out="$("$@" 2>&1)" || rc=$?
  if [[ $rc -eq 0 ]]; then
    printf '  ✅  PASS — %s\n' "$label"
    ((_ASSERT_PASS++)) || true
  else
    printf '  ❌  FAIL — %s (exit %d)\n' "$label" "$rc"
    [[ -n "$out" ]] && printf '         %s\n' "$out"
    _ASSERT_FAILURES+=("$label")
    ((_ASSERT_FAIL++)) || true
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
    ((_ASSERT_PASS++)) || true
  else
    printf '  ❌  FAIL (expected non-zero, got 0) — %s\n' "$label"
    [[ -n "$out" ]] && printf '         %s\n' "$out"
    _ASSERT_FAILURES+=("$label")
    ((_ASSERT_FAIL++)) || true
  fi
}

reportResults() {
  echo ""
  echo "Results: ${_ASSERT_PASS} passed, ${_ASSERT_FAIL} failed."
  if [[ ${_ASSERT_FAIL} -gt 0 ]]; then
    echo "Failed checks:"
    for _f in "${_ASSERT_FAILURES[@]}"; do
      printf '  — %s\n' "$_f"
    done
    exit 1
  fi
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
