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
  run net::fetch_with_retry 3 0 _passing_cmd
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
  run net::fetch_with_retry 3 0 _retry_cmd
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
  run net::fetch_with_retry 2 0 _always_fail
  assert_failure
  assert_output --partial "Failed after 2"
}

# ---------------------------------------------------------------------------
# _net_ensure_fetch_tool  (tool detection and caching)
# ---------------------------------------------------------------------------

@test "_net_ensure_fetch_tool detects curl and sets _NET_FETCH_TOOL" {
  reload_lib net.sh
  # Provide a fake curl; _net_ensure_ca_certs needs to be stubbed as well.
  create_fake_bin "curl" ""
  prepend_fake_bin_path
  # Stub _net_ensure_ca_certs to avoid ospkg dependency.
  _net_ensure_ca_certs() {
    _NET_CA_CERTS_OK=true
    return 0
  }
  export -f _net_ensure_ca_certs
  _net_ensure_fetch_tool
  [[ "$_NET_FETCH_TOOL" == "curl" ]]
}

@test "_net_ensure_fetch_tool detects wget when curl is absent" {
  reload_lib net.sh
  create_fake_bin "wget" ""
  # Temporarily restrict PATH to only the fake bin dir so the real curl
  # (e.g. /usr/local/bin/curl) is not found.  PATH is restored before
  # returning so bats cleanup commands (rm, etc.) can still find their tools.
  local _saved_path="$PATH"
  export PATH="${BATS_TEST_TMPDIR}/bin"
  _net_ensure_ca_certs() {
    _NET_CA_CERTS_OK=true
    return 0
  }
  export -f _net_ensure_ca_certs
  _net_ensure_fetch_tool
  local _result="$_NET_FETCH_TOOL"
  export PATH="$_saved_path"
  [[ "$_result" == "wget" ]]
}

@test "_net_ensure_fetch_tool is idempotent when _NET_FETCH_TOOL is set" {
  reload_lib net.sh
  _NET_FETCH_TOOL="curl"
  _NET_CA_CERTS_OK=true
  _net_ensure_ca_certs() { return 0; }
  export -f _net_ensure_ca_certs
  _net_ensure_fetch_tool
  [[ "$_NET_FETCH_TOOL" == "curl" ]]
}

# ---------------------------------------------------------------------------
# _net_ensure_ca_certs  (caching and Darwin short-circuit)
# ---------------------------------------------------------------------------

@test "_net_ensure_ca_certs is a no-op when already cached" {
  reload_lib net.sh
  _NET_CA_CERTS_OK=true
  # If idempotency guard works, the function must return 0 immediately
  # without touching any file paths or calling ospkg.
  run _net_ensure_ca_certs
  assert_success
}

@test "_net_ensure_ca_certs is a no-op on Darwin" {
  reload_lib net.sh
  uname() { echo "Darwin"; }
  export -f uname
  run _net_ensure_ca_certs
  assert_success
  # Verify that _NET_CA_CERTS_OK was set inside the call by re-running in a
  # subshell that checks the flag after the call returns.
  run bash -c "
    source '${BATS_TEST_DIRNAME}/../../lib/net.sh'
    uname() { echo 'Darwin'; }
    export -f uname
    _net_ensure_ca_certs
    [[ \"\${_NET_CA_CERTS_OK}\" == 'true' ]] && echo 'CACHED'
  "
  assert_output --partial "CACHED"
}

# ---------------------------------------------------------------------------
# net::fetch_url_stdout  /  net::fetch_url_file  (routing tests)
# ---------------------------------------------------------------------------

@test "net::fetch_url_stdout routes to curl when _NET_FETCH_TOOL=curl" {
  reload_lib net.sh
  _NET_FETCH_TOOL=curl
  _NET_CA_CERTS_OK=true
  curl() {
    echo "curl $*"
    return 0
  }
  export -f curl
  run net::fetch_url_stdout "https://example.com"
  assert_output --partial "curl"
  assert_output --partial "--retry 60"
  assert_output --partial "--compressed"
}

@test "net::fetch_url_stdout routes to wget when _NET_FETCH_TOOL=wget" {
  reload_lib net.sh
  _NET_FETCH_TOOL=wget
  _NET_CA_CERTS_OK=true
  net::fetch_with_retry() {
    echo "retry=$1 delay=$2 tool=$3"
    return 0
  }
  export -f net::fetch_with_retry
  run net::fetch_url_stdout "https://example.com"
  assert_output --partial "tool=wget"
  assert_output --partial "retry=60"
  assert_output --partial "delay=5"
}

@test "net::fetch_url_file routes to curl when _NET_FETCH_TOOL=curl" {
  reload_lib net.sh
  _NET_FETCH_TOOL=curl
  _NET_CA_CERTS_OK=true
  curl() {
    echo "curl $*"
    return 0
  }
  export -f curl
  run net::fetch_url_file "https://example.com" "/tmp/out"
  assert_output --partial "curl"
  assert_output --partial "--retry 60"
  assert_output --partial "--compressed"
}

@test "net::fetch_url_file routes to wget when _NET_FETCH_TOOL=wget" {
  reload_lib net.sh
  _NET_FETCH_TOOL=wget
  _NET_CA_CERTS_OK=true
  net::fetch_with_retry() {
    echo "retry=$1 delay=$2 tool=$3"
    return 0
  }
  export -f net::fetch_with_retry
  run net::fetch_url_file "https://example.com" "/tmp/out"
  assert_output --partial "tool=wget"
  assert_output --partial "retry=60"
  assert_output --partial "delay=5"
}

@test "net::fetch_url_stdout passes --retries to curl" {
  reload_lib net.sh
  _NET_FETCH_TOOL=curl
  _NET_CA_CERTS_OK=true
  curl() {
    echo "curl $*"
    return 0
  }
  export -f curl
  run net::fetch_url_stdout "https://example.com" --retries 3
  assert_output --partial "--retry 3"
}

@test "net::fetch_url_stdout passes --retries to wget" {
  reload_lib net.sh
  _NET_FETCH_TOOL=wget
  _NET_CA_CERTS_OK=true
  net::fetch_with_retry() {
    echo "retry=$1 delay=$2 tool=$3"
    return 0
  }
  export -f net::fetch_with_retry
  run net::fetch_url_stdout "https://example.com" --retries 3
  assert_output --partial "retry=3"
}

@test "net::fetch_url_file passes --retries to curl" {
  reload_lib net.sh
  _NET_FETCH_TOOL=curl
  _NET_CA_CERTS_OK=true
  curl() {
    echo "curl $*"
    return 0
  }
  export -f curl
  run net::fetch_url_file "https://example.com" "/tmp/out" --retries 3
  assert_output --partial "--retry 3"
}

@test "net::fetch_url_file passes --retries to wget" {
  reload_lib net.sh
  _NET_FETCH_TOOL=wget
  _NET_CA_CERTS_OK=true
  net::fetch_with_retry() {
    echo "retry=$1 delay=$2 tool=$3"
    return 0
  }
  export -f net::fetch_with_retry
  run net::fetch_url_file "https://example.com" "/tmp/out" --retries 3
  assert_output --partial "retry=3"
}

@test "net::fetch_url_stdout passes --delay to curl" {
  reload_lib net.sh
  _NET_FETCH_TOOL=curl
  _NET_CA_CERTS_OK=true
  curl() {
    echo "curl $*"
    return 0
  }
  export -f curl
  run net::fetch_url_stdout "https://example.com" --delay 10
  assert_output --partial "--retry-delay 10"
}

@test "net::fetch_url_stdout passes --delay to wget" {
  reload_lib net.sh
  _NET_FETCH_TOOL=wget
  _NET_CA_CERTS_OK=true
  net::fetch_with_retry() {
    echo "retry=$1 delay=$2 tool=$3"
    return 0
  }
  export -f net::fetch_with_retry
  run net::fetch_url_stdout "https://example.com" --delay 10
  assert_output --partial "delay=10"
}

@test "net::fetch_url_file passes --delay to curl" {
  reload_lib net.sh
  _NET_FETCH_TOOL=curl
  _NET_CA_CERTS_OK=true
  curl() {
    echo "curl $*"
    return 0
  }
  export -f curl
  run net::fetch_url_file "https://example.com" "/tmp/out" --delay 10
  assert_output --partial "--retry-delay 10"
}

@test "net::fetch_url_file passes --delay to wget" {
  reload_lib net.sh
  _NET_FETCH_TOOL=wget
  _NET_CA_CERTS_OK=true
  net::fetch_with_retry() {
    echo "retry=$1 delay=$2 tool=$3"
    return 0
  }
  export -f net::fetch_with_retry
  run net::fetch_url_file "https://example.com" "/tmp/out" --delay 10
  assert_output --partial "delay=10"
}

@test "net::fetch_url_stdout passes --header to curl as -H pairs" {
  reload_lib net.sh
  _NET_FETCH_TOOL=curl
  _NET_CA_CERTS_OK=true
  curl() {
    printf '%s\n' "$@"
    return 0
  }
  export -f curl
  run net::fetch_url_stdout "https://example.com" \
    --header "Accept: application/json" \
    --header "Authorization: Bearer mytoken"
  assert_output --partial "-H"
  assert_output --partial "Accept: application/json"
  assert_output --partial "Authorization: Bearer mytoken"
}

@test "net::fetch_url_stdout passes --header to wget as --header=K: V" {
  reload_lib net.sh
  _NET_FETCH_TOOL=wget
  _NET_CA_CERTS_OK=true
  net::fetch_with_retry() {
    printf '%s\n' "$@"
    return 0
  }
  export -f net::fetch_with_retry
  run net::fetch_url_stdout "https://example.com" \
    --header "Accept: application/json" \
    --header "Authorization: Bearer mytoken"
  assert_output --partial "--header=Accept: application/json"
  assert_output --partial "--header=Authorization: Bearer mytoken"
}

@test "net::fetch_url_file passes --header to curl as -H pairs" {
  reload_lib net.sh
  _NET_FETCH_TOOL=curl
  _NET_CA_CERTS_OK=true
  curl() {
    printf '%s\n' "$@"
    return 0
  }
  export -f curl
  run net::fetch_url_file "https://example.com" "/tmp/out" \
    --header "Accept: application/json" \
    --header "Authorization: Bearer mytoken"
  assert_output --partial "-H"
  assert_output --partial "Accept: application/json"
  assert_output --partial "Authorization: Bearer mytoken"
}

@test "net::fetch_url_file passes --header to wget as --header=K: V" {
  reload_lib net.sh
  _NET_FETCH_TOOL=wget
  _NET_CA_CERTS_OK=true
  net::fetch_with_retry() {
    printf '%s\n' "$@"
    return 0
  }
  export -f net::fetch_with_retry
  run net::fetch_url_file "https://example.com" "/tmp/out" \
    --header "Accept: application/json" \
    --header "Authorization: Bearer mytoken"
  assert_output --partial "--header=Accept: application/json"
  assert_output --partial "--header=Authorization: Bearer mytoken"
}

@test "net::fetch_url_stdout rejects unknown option" {
  reload_lib net.sh
  _NET_FETCH_TOOL=curl
  _NET_CA_CERTS_OK=true
  run net::fetch_url_stdout "https://example.com" --bogus foo
  assert_failure
  assert_output --partial "unknown option"
}

@test "net::fetch_url_file rejects unknown option" {
  reload_lib net.sh
  _NET_FETCH_TOOL=curl
  _NET_CA_CERTS_OK=true
  run net::fetch_url_file "https://example.com" "/tmp/out" --bogus foo
  assert_failure
  assert_output --partial "unknown option"
}
