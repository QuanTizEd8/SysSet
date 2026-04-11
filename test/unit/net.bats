#!/usr/bin/env bats
# Unit tests for lib/net.sh
#
# net::fetch_url_stdout / net::fetch_url_file rely on curl/wget network access
# and are exercised at the feature integration level.  These unit tests focus
# on the locally-testable retry logic and on the tool-detection caching.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
}

# ---------------------------------------------------------------------------
# net::fetch_with_retry
# ---------------------------------------------------------------------------

@test "net::fetch_with_retry succeeds on the first attempt" {
  reload_lib net.sh
  local _count=0
  _passing_cmd() {
    _count=$((_count + 1))
    return 0
  }
  export -f _passing_cmd
  run net::fetch_with_retry 3 _passing_cmd
  assert_success
}

@test "net::fetch_with_retry retries on failure then succeeds" {
  reload_lib net.sh
  # Write a counter file and succeed on the second attempt.
  local _counter="${BATS_TEST_TMPDIR}/attempts"
  printf '0' > "$_counter"
  create_fake_bin "_retry_cmd" ""
  # Override with a script that fails once then succeeds.
  cat > "${BATS_TEST_TMPDIR}/bin/_retry_cmd" << 'EOF'
#!/bin/sh
counter_file="${BATS_TEST_TMPDIR}/attempts"
n="$(cat "$counter_file")"
n=$((n + 1))
printf '%s' "$n" > "$counter_file"
[ "$n" -ge 2 ] && exit 0 || exit 1
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/_retry_cmd"
  prepend_fake_bin_path
  run net::fetch_with_retry 3 _retry_cmd
  assert_success
}

@test "net::fetch_with_retry exhausts all attempts and fails" {
  reload_lib net.sh
  create_fake_bin "_always_fail" ""
  cat > "${BATS_TEST_TMPDIR}/bin/_always_fail" << 'EOF'
#!/bin/sh
exit 1
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/_always_fail"
  prepend_fake_bin_path
  # Override sleep to a no-op so the test is fast.
  sleep() { :; }
  export -f sleep
  run net::fetch_with_retry 2 _always_fail
  assert_failure
  assert_output --partial "Failed after 2"
}

# ---------------------------------------------------------------------------
# net::ensure_fetch_tool  (tool detection and caching)
# ---------------------------------------------------------------------------

@test "net::ensure_fetch_tool detects curl and sets _NET_FETCH_TOOL" {
  reload_lib net.sh
  # Provide a fake curl; ensure_ca_certs needs to be stubbed as well.
  create_fake_bin "curl" ""
  prepend_fake_bin_path
  # Stub net::ensure_ca_certs to avoid ospkg dependency.
  net::ensure_ca_certs() {
    _NET_CA_CERTS_OK=true
    return 0
  }
  export -f net::ensure_ca_certs
  net::ensure_fetch_tool
  [[ "$_NET_FETCH_TOOL" == "curl" ]]
}

@test "net::ensure_fetch_tool detects wget when curl is absent" {
  reload_lib net.sh
  create_fake_bin "wget" ""
  # Temporarily restrict PATH to only the fake bin dir so the real curl
  # (e.g. /usr/local/bin/curl) is not found.  PATH is restored before
  # returning so bats cleanup commands (rm, etc.) can still find their tools.
  local _saved_path="$PATH"
  export PATH="${BATS_TEST_TMPDIR}/bin"
  net::ensure_ca_certs() {
    _NET_CA_CERTS_OK=true
    return 0
  }
  export -f net::ensure_ca_certs
  net::ensure_fetch_tool
  local _result="$_NET_FETCH_TOOL"
  export PATH="$_saved_path"
  [[ "$_result" == "wget" ]]
}

@test "net::ensure_fetch_tool is idempotent when _NET_FETCH_TOOL is set" {
  reload_lib net.sh
  _NET_FETCH_TOOL="curl"
  _NET_CA_CERTS_OK=true
  net::ensure_ca_certs() { return 0; }
  export -f net::ensure_ca_certs
  net::ensure_fetch_tool
  [[ "$_NET_FETCH_TOOL" == "curl" ]]
}
