#!/usr/bin/env bats
# Unit tests for lib/net.bash
#
# net__fetch_url_stdout / net__fetch_url_file rely on curl/wget network access
# and are exercised at the feature integration level.  These unit tests focus
# on the locally-testable retry logic and on the tool-detection caching.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
}

# ---------------------------------------------------------------------------
# net__fetch_with_retry
# ---------------------------------------------------------------------------

@test "net__fetch_with_retry succeeds on the first attempt" {
  reload_lib
  local _count=0
  _passing_cmd() {
    _count=$((_count + 1))
    return 0
  }
  export -f _passing_cmd
  run net__fetch_with_retry --retries 3 --delay 0 _passing_cmd
  assert_success
}

@test "net__fetch_with_retry retries on failure then succeeds" {
  reload_lib
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
  run net__fetch_with_retry --retries 3 --delay 0 _retry_cmd
  assert_success
}

@test "net__fetch_with_retry exhausts all attempts and fails" {
  reload_lib
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
  run net__fetch_with_retry --retries 2 --delay 0 _always_fail
  assert_failure
  assert_output --partial "Failed after 2"
}

@test "_net__fetch returns 1 when ensure fails under errexit-off caller (github API path)" {
  reload_lib
  _net__ensure_fetch_tool() { return 1; }
  export -f _net__ensure_fetch_tool
  local _rc=0
  _net__fetch "https://example.com" "" || _rc=$?
  [[ "$_rc" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# _net__ensure_fetch_tool  (tool detection and caching)
# ---------------------------------------------------------------------------

@test "_net__ensure_fetch_tool detects curl and sets _NET__FETCH_TOOL" {
  reload_lib
  # Provide a fake curl; bootstrap__ca_certs needs to be stubbed as well.
  create_fake_bin "curl" ""
  prepend_fake_bin_path
  # Stub bootstrap__ca_certs to avoid ospkg dependency.
  bootstrap__ca_certs() { return 0; }
  export -f bootstrap__ca_certs
  _net__ensure_fetch_tool
  [[ "$_NET__FETCH_TOOL" == "curl" ]]
}

@test "_net__ensure_fetch_tool detects wget when curl is absent" {
  reload_lib
  create_fake_bin "wget" ""
  # Temporarily isolate PATH so the real curl (e.g. /usr/local/bin/curl)
  # is not found.
  begin_path_isolation
  bootstrap__ca_certs() { return 0; }
  export -f bootstrap__ca_certs
  _net__ensure_fetch_tool
  local _result="$_NET__FETCH_TOOL"
  end_path_isolation
  [[ "$_result" == "wget" ]]
}

@test "_net__ensure_fetch_tool is idempotent when _NET__FETCH_TOOL is set" {
  reload_lib
  _NET__FETCH_TOOL="curl"
  bootstrap__ca_certs() { return 0; }
  export -f bootstrap__ca_certs
  _net__ensure_fetch_tool
  [[ "$_NET__FETCH_TOOL" == "curl" ]]
}

@test "_net__ensure_fetch_tool skips snap-packaged curl and falls back to wget" {
  reload_lib
  # Override 'command' so that curl appears to live under /snap/ (sandboxed).
  # The snap check is: case "$(command -v curl)" in /snap/*).
  command() {
    if [[ "$1" == "-v" && "${2:-}" == "curl" ]]; then
      echo "/snap/bin/curl"
      return 0
    fi
    builtin command "$@"
  }
  export -f command
  create_fake_bin "wget" ""
  prepend_fake_bin_path
  bootstrap__ca_certs() { return 0; }
  export -f bootstrap__ca_certs
  _net__ensure_fetch_tool
  [[ "$_NET__FETCH_TOOL" == "wget" ]]
}

@test "_net__ensure_fetch_tool emits a warning when snap curl is detected" {
  reload_lib
  command() {
    if [[ "$1" == "-v" && "${2:-}" == "curl" ]]; then
      echo "/snap/bin/curl"
      return 0
    fi
    builtin command "$@"
  }
  export -f command
  create_fake_bin "wget" ""
  prepend_fake_bin_path
  bootstrap__ca_certs() { return 0; }
  export -f bootstrap__ca_certs
  run _net__ensure_fetch_tool
  assert_success
  assert_output --partial "snap"
}

# ---------------------------------------------------------------------------
# _net__ensure_ca_certs  (caching and Darwin short-circuit)
# ---------------------------------------------------------------------------

@test "bootstrap__ca_certs returns 0 when CA bundle is already present" {
  reload_lib
  # Force the precondition deterministically instead of relying on it already
  # being true on disk — whether a real bundle is present depends on the base
  # image and (in the full suite) on integration/bootstrap.bats's unmocked
  # install having already run earlier in the same container session. This
  # test must be self-contained: it should pass the same way whether run as
  # part of the full suite or in isolation (e.g. `--module net`).
  #
  # macOS short-circuits before ever checking bundle paths (see
  # bootstrap__ca_certs's own uname check below), so there's no precondition
  # to force there — and /etc/ssl/certs/ isn't writable by the test runner on
  # macOS anyway (it's not even the real bundle location on that OS).
  _created_ca_bundle=false
  if [ "$(uname -s)" != "Darwin" ]; then
    _ca_bundle="/etc/ssl/certs/ca-certificates.crt"
    if [ ! -s "$_ca_bundle" ]; then
      mkdir -p "$(dirname "$_ca_bundle")"
      printf 'fake bundle for test\n' > "$_ca_bundle"
      _created_ca_bundle=true
    fi
  fi

  # ospkg__install_tracked is stubbed to fail; if bootstrap__ca_certs tries to
  # install ca-certificates it will fail, proving the bundle was found directly.
  ospkg__install_tracked() { return 1; }
  export -f ospkg__install_tracked
  run bootstrap__ca_certs
  assert_success
}

@test "bootstrap__ca_certs returns 0 on Darwin" {
  reload_lib
  uname() { echo "Darwin"; }
  export -f uname
  run bootstrap__ca_certs
  assert_success
}

teardown() {
  if [ "${_created_ca_bundle:-false}" = true ]; then
    rm -f "$_ca_bundle"
  fi
}

# ---------------------------------------------------------------------------
# net__fetch_url_stdout  /  net__fetch_url_file  (routing tests)
# ---------------------------------------------------------------------------

@test "net__fetch_url_stdout routes to curl when _NET__FETCH_TOOL=curl" {
  reload_lib
  _NET__FETCH_TOOL=curl
  _NET__CA_CERTS_OK=true
  curl() {
    echo "curl $*"
    return 0
  }
  export -f curl
  run net__fetch_url_stdout "https://example.com"
  assert_output --partial "curl"
  assert_output --partial "--retry 60"
  assert_output --partial "--compressed"
  assert_output --partial "User-Agent: devfeats"
}

@test "net__fetch_url_stdout routes to wget when _NET__FETCH_TOOL=wget" {
  reload_lib
  _NET__FETCH_TOOL=wget
  _NET__CA_CERTS_OK=true
  net__fetch_with_retry() {
    local _r _d
    while [ $# -gt 0 ]; do
      case "$1" in
        --retries)
          _r="$2"
          shift 2
          ;;
        --delay)
          _d="$2"
          shift 2
          ;;
        *) break ;;
      esac
    done
    echo "retry=${_r} delay=${_d} tool=$1"
    return 0
  }
  export -f net__fetch_with_retry
  run net__fetch_url_stdout "https://example.com"
  assert_output --partial "tool=wget"
  assert_output --partial "retry=60"
  assert_output --partial "delay=5"
}

@test "net__fetch_url_file routes to curl when _NET__FETCH_TOOL=curl" {
  reload_lib
  _NET__FETCH_TOOL=curl
  _NET__CA_CERTS_OK=true
  curl() {
    echo "curl $*"
    return 0
  }
  export -f curl
  run net__fetch_url_file "https://example.com" "/tmp/out"
  assert_output --partial "curl"
  assert_output --partial "--retry 60"
  assert_output --partial "--compressed"
  assert_output --partial "User-Agent: devfeats"
}

@test "net__fetch_url_stdout returns failure when curl fails" {
  reload_lib
  _NET__FETCH_TOOL=curl
  _NET__CA_CERTS_OK=true
  curl() {
    return 22
  }
  export -f curl
  run net__fetch_url_stdout "https://example.com/missing"
  assert_failure
  assert_output --partial "failed to fetch"
  assert_output --partial "exit 22"
}

@test "net__fetch_url_file returns failure when curl fails" {
  reload_lib
  _NET__FETCH_TOOL=curl
  _NET__CA_CERTS_OK=true
  curl() {
    return 22
  }
  export -f curl
  run net__fetch_url_file "https://example.com/missing" "/tmp/out"
  assert_failure
  assert_output --partial "failed to fetch"
  assert_output --partial "exit 22"
}

@test "net__fetch_url_stdout does not override an explicit User-Agent header" {
  reload_lib
  _NET__FETCH_TOOL=curl
  _NET__CA_CERTS_OK=true
  curl() {
    printf '%s\n' "$@"
    return 0
  }
  export -f curl
  run net__fetch_url_stdout "https://example.com" --header "User-Agent: other/1"
  assert_output --partial "User-Agent: other/1"
  refute_output --partial "User-Agent: devfeats"
}

@test "net__fetch_url_file routes to wget when _NET__FETCH_TOOL=wget" {
  reload_lib
  _NET__FETCH_TOOL=wget
  _NET__CA_CERTS_OK=true
  net__fetch_with_retry() {
    local _r _d
    while [ $# -gt 0 ]; do
      case "$1" in
        --retries)
          _r="$2"
          shift 2
          ;;
        --delay)
          _d="$2"
          shift 2
          ;;
        *) break ;;
      esac
    done
    echo "retry=${_r} delay=${_d} tool=$1"
    return 0
  }
  export -f net__fetch_with_retry
  run net__fetch_url_file "https://example.com" "/tmp/out"
  assert_output --partial "tool=wget"
  assert_output --partial "retry=60"
  assert_output --partial "delay=5"
}

@test "net__fetch_url_stdout returns failure when wget retry helper fails" {
  reload_lib
  _NET__FETCH_TOOL=wget
  _NET__CA_CERTS_OK=true
  net__fetch_with_retry() {
    return 1
  }
  export -f net__fetch_with_retry
  run net__fetch_url_stdout "https://example.com/missing"
  assert_failure
  assert_output --partial "failed to fetch"
  assert_output --partial "with wget"
}

@test "net__fetch_url_stdout passes --retries to curl" {
  reload_lib
  _NET__FETCH_TOOL=curl
  _NET__CA_CERTS_OK=true
  curl() {
    echo "curl $*"
    return 0
  }
  export -f curl
  run net__fetch_url_stdout "https://example.com" --retries 3
  assert_output --partial "--retry 3"
}

@test "net__fetch_url_stdout passes --retries to wget" {
  reload_lib
  _NET__FETCH_TOOL=wget
  _NET__CA_CERTS_OK=true
  net__fetch_with_retry() {
    local _r _d
    while [ $# -gt 0 ]; do
      case "$1" in
        --retries)
          _r="$2"
          shift 2
          ;;
        --delay)
          _d="$2"
          shift 2
          ;;
        *) break ;;
      esac
    done
    echo "retry=${_r} delay=${_d} tool=$1"
    return 0
  }
  export -f net__fetch_with_retry
  run net__fetch_url_stdout "https://example.com" --retries 3
  assert_output --partial "retry=3"
}

@test "net__fetch_url_file passes --retries to curl" {
  reload_lib
  _NET__FETCH_TOOL=curl
  _NET__CA_CERTS_OK=true
  curl() {
    echo "curl $*"
    return 0
  }
  export -f curl
  run net__fetch_url_file "https://example.com" "/tmp/out" --retries 3
  assert_output --partial "--retry 3"
}

@test "net__fetch_url_file passes --retries to wget" {
  reload_lib
  _NET__FETCH_TOOL=wget
  _NET__CA_CERTS_OK=true
  net__fetch_with_retry() {
    local _r _d
    while [ $# -gt 0 ]; do
      case "$1" in
        --retries)
          _r="$2"
          shift 2
          ;;
        --delay)
          _d="$2"
          shift 2
          ;;
        *) break ;;
      esac
    done
    echo "retry=${_r} delay=${_d} tool=$1"
    return 0
  }
  export -f net__fetch_with_retry
  run net__fetch_url_file "https://example.com" "/tmp/out" --retries 3
  assert_output --partial "retry=3"
}

@test "net__fetch_url_file returns failure when wget retry helper fails" {
  reload_lib
  _NET__FETCH_TOOL=wget
  _NET__CA_CERTS_OK=true
  net__fetch_with_retry() {
    return 1
  }
  export -f net__fetch_with_retry
  run net__fetch_url_file "https://example.com/missing" "/tmp/out"
  assert_failure
  assert_output --partial "failed to fetch"
  assert_output --partial "with wget"
}

@test "net__fetch_url_stdout passes --delay to curl" {
  reload_lib
  _NET__FETCH_TOOL=curl
  _NET__CA_CERTS_OK=true
  curl() {
    echo "curl $*"
    return 0
  }
  export -f curl
  run net__fetch_url_stdout "https://example.com" --delay 10
  assert_output --partial "--retry-delay 10"
}

@test "net__fetch_url_stdout passes --delay to wget" {
  reload_lib
  _NET__FETCH_TOOL=wget
  _NET__CA_CERTS_OK=true
  net__fetch_with_retry() {
    local _r _d
    while [ $# -gt 0 ]; do
      case "$1" in
        --retries)
          _r="$2"
          shift 2
          ;;
        --delay)
          _d="$2"
          shift 2
          ;;
        *) break ;;
      esac
    done
    echo "retry=${_r} delay=${_d} tool=$1"
    return 0
  }
  export -f net__fetch_with_retry
  run net__fetch_url_stdout "https://example.com" --delay 10
  assert_output --partial "delay=10"
}

@test "net__fetch_url_file passes --delay to curl" {
  reload_lib
  _NET__FETCH_TOOL=curl
  _NET__CA_CERTS_OK=true
  curl() {
    echo "curl $*"
    return 0
  }
  export -f curl
  run net__fetch_url_file "https://example.com" "/tmp/out" --delay 10
  assert_output --partial "--retry-delay 10"
}

@test "net__fetch_url_file passes --delay to wget" {
  reload_lib
  _NET__FETCH_TOOL=wget
  _NET__CA_CERTS_OK=true
  net__fetch_with_retry() {
    local _r _d
    while [ $# -gt 0 ]; do
      case "$1" in
        --retries)
          _r="$2"
          shift 2
          ;;
        --delay)
          _d="$2"
          shift 2
          ;;
        *) break ;;
      esac
    done
    echo "retry=${_r} delay=${_d} tool=$1"
    return 0
  }
  export -f net__fetch_with_retry
  run net__fetch_url_file "https://example.com" "/tmp/out" --delay 10
  assert_output --partial "delay=10"
}

@test "net__fetch_url_stdout passes --header to curl as -H pairs" {
  reload_lib
  _NET__FETCH_TOOL=curl
  _NET__CA_CERTS_OK=true
  curl() {
    printf '%s\n' "$@"
    return 0
  }
  export -f curl
  run net__fetch_url_stdout "https://example.com" \
    --header "Accept: application/json" \
    --header "Authorization: Bearer mytoken"
  assert_output --partial "-H"
  assert_output --partial "Accept: application/json"
  assert_output --partial "Authorization: Bearer mytoken"
}

@test "net__fetch_url_stdout passes --header to wget as --header=K: V" {
  reload_lib
  _NET__FETCH_TOOL=wget
  _NET__CA_CERTS_OK=true
  net__fetch_with_retry() {
    printf '%s\n' "$@"
    return 0
  }
  export -f net__fetch_with_retry
  run net__fetch_url_stdout "https://example.com" \
    --header "Accept: application/json" \
    --header "Authorization: Bearer mytoken"
  assert_output --partial "--header=Accept: application/json"
  assert_output --partial "--header=Authorization: Bearer mytoken"
}

@test "net__fetch_url_file passes --header to curl as -H pairs" {
  reload_lib
  _NET__FETCH_TOOL=curl
  _NET__CA_CERTS_OK=true
  curl() {
    printf '%s\n' "$@"
    return 0
  }
  export -f curl
  run net__fetch_url_file "https://example.com" "/tmp/out" \
    --header "Accept: application/json" \
    --header "Authorization: Bearer mytoken"
  assert_output --partial "-H"
  assert_output --partial "Accept: application/json"
  assert_output --partial "Authorization: Bearer mytoken"
}

@test "net__fetch_url_file passes --header to wget as --header=K: V" {
  reload_lib
  _NET__FETCH_TOOL=wget
  _NET__CA_CERTS_OK=true
  net__fetch_with_retry() {
    printf '%s\n' "$@"
    return 0
  }
  export -f net__fetch_with_retry
  run net__fetch_url_file "https://example.com" "/tmp/out" \
    --header "Accept: application/json" \
    --header "Authorization: Bearer mytoken"
  assert_output --partial "--header=Accept: application/json"
  assert_output --partial "--header=Authorization: Bearer mytoken"
}

@test "net__fetch_url_stdout rejects unknown option" {
  reload_lib
  _NET__FETCH_TOOL=curl
  _NET__CA_CERTS_OK=true
  run net__fetch_url_stdout "https://example.com" --bogus foo
  assert_failure
  assert_output --partial "unknown option"
}

@test "net__fetch_url_file rejects unknown option" {
  reload_lib
  _NET__FETCH_TOOL=curl
  _NET__CA_CERTS_OK=true
  run net__fetch_url_file "https://example.com" "/tmp/out" --bogus foo
  assert_failure
  assert_output --partial "unknown option"
}
