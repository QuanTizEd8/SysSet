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

@test "net__fetch_with_retry retries only when --retry-if classifies the failure" {
  reload_lib
  local _counter="${BATS_TEST_TMPDIR}/attempts"
  printf '0' > "$_counter"
  _retry_if() { grep -qi transient "$2"; }
  _transient_cmd() {
    local _n
    _n=$(($(cat "$_counter") + 1))
    printf '%s' "$_n" > "$_counter"
    if [[ "$_n" -eq 1 ]]; then
      printf 'transient connection reset\n' >&2
      return 1
    fi
    return 0
  }
  export -f _retry_if _transient_cmd
  run net__fetch_with_retry --retries 2 --delay 0 --retry-if _retry_if _transient_cmd
  assert_success
  assert [ "$(cat "$_counter")" -eq 2 ]
}

@test "net__fetch_with_retry stops immediately when --retry-if rejects the failure" {
  reload_lib
  local _counter="${BATS_TEST_TMPDIR}/attempts"
  printf '0' > "$_counter"
  _retry_if() { grep -qi transient "$2"; }
  _permanent_cmd() {
    printf '%s' "$(($(cat "$_counter") + 1))" > "$_counter"
    printf 'authentication failed\n' >&2
    return 1
  }
  export -f _retry_if _permanent_cmd
  run net__fetch_with_retry --retries 3 --delay 0 --retry-if _retry_if _permanent_cmd
  assert_failure
  assert [ "$(cat "$_counter")" -eq 1 ]
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

@test "net__fetch_with_retry --retry-if emits only the winning attempt's stdout" {
  reload_lib
  # A failed attempt that writes partial stdout before retrying must NOT leak
  # that output into the caller's capture; only the successful (final) attempt's
  # stdout may be emitted. Otherwise git__resolve_ref's `head -1` can pick a
  # truncated SHA from a dropped connection.
  local _counter="${BATS_TEST_TMPDIR}/attempts"
  printf '0' > "$_counter"
  _retry_if() { [ "$1" -ne 0 ]; }
  _partial_then_ok() {
    local _n
    _n=$(($(cat "$_counter") + 1))
    printf '%s' "$_n" > "$_counter"
    if [[ "$_n" -eq 1 ]]; then
      printf 'partialsha123\trefs/heads/main\n'
      printf 'connection reset by peer\n' >&2
      return 1
    fi
    printf 'GOODSHA456\trefs/heads/main\n'
    return 0
  }
  export -f _retry_if _partial_then_ok
  run --separate-stderr net__fetch_with_retry --retries 3 --delay 0 --retry-if _retry_if _partial_then_ok
  assert_success
  assert [ "$(cat "$_counter")" -eq 2 ]
  assert_output --partial 'GOODSHA456'
  refute_output --partial 'partialsha123'
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
# net__fetch_url_stdout / net__fetch_url_file (deterministic fetch tests)
# ---------------------------------------------------------------------------

_net_test__curl_success() {
  local _output='' _headers='' _write_out='' _arg
  : > "${BATS_TEST_TMPDIR}/curl.args"
  while [ $# -gt 0 ]; do
    _arg="$1"
    printf '%s\n' "$_arg" >> "${BATS_TEST_TMPDIR}/curl.args"
    case "$_arg" in
      -o)
        _output="$2"
        printf '%s\n' "$2" >> "${BATS_TEST_TMPDIR}/curl.args"
        shift 2
        ;;
      -D)
        _headers="$2"
        printf '%s\n' "$2" >> "${BATS_TEST_TMPDIR}/curl.args"
        shift 2
        ;;
      -w)
        _write_out="$2"
        printf '%s\n' "$2" >> "${BATS_TEST_TMPDIR}/curl.args"
        shift 2
        ;;
      *) shift ;;
    esac
  done
  printf 'data' > "$_output"
  printf 'HTTP/1.1 200 OK\r\n\r\n' > "$_headers"
  [ "$_write_out" = '%{http_code}' ] && printf '200'
}

_net_test__wget_success() {
  local _output='' _arg
  : > "${BATS_TEST_TMPDIR}/wget.args"
  while [ $# -gt 0 ]; do
    _arg="$1"
    printf '%s\n' "$_arg" >> "${BATS_TEST_TMPDIR}/wget.args"
    case "$_arg" in
      -O)
        _output="$2"
        printf '%s\n' "$2" >> "${BATS_TEST_TMPDIR}/wget.args"
        shift 2
        ;;
      *) shift ;;
    esac
  done
  printf 'data' > "$_output"
  printf '  HTTP/1.1 200 OK\n' >&2
}

@test "net__fetch_url_stdout fetches through curl with shared retry arguments" {
  reload_lib
  _NET__FETCH_TOOL=curl
  _NET__CA_CERTS_OK=true
  curl() { _net_test__curl_success "$@"; }
  export -f curl _net_test__curl_success
  run net__fetch_url_stdout "https://example.com" \
    --retries 3 --delay 10 \
    --header "Accept: application/json" \
    --header "User-Agent: other/1"
  assert_success
  assert_output --partial 'data'
  grep -Fx -- '--http1.1' "${BATS_TEST_TMPDIR}/curl.args"
  grep -Fx -- '--compressed' "${BATS_TEST_TMPDIR}/curl.args"
  grep -Fx -- 'Accept: application/json' "${BATS_TEST_TMPDIR}/curl.args"
  grep -Fx -- 'User-Agent: other/1' "${BATS_TEST_TMPDIR}/curl.args"
  run grep -F -- '--retry' "${BATS_TEST_TMPDIR}/curl.args"
  assert_failure
}

@test "net__probe_url uses a HEAD request through the shared transport" {
  reload_lib
  _NET__FETCH_TOOL=curl
  _NET__CA_CERTS_OK=true
  curl() { _net_test__curl_success "$@"; }
  export -f curl _net_test__curl_success
  run net__probe_url "https://example.com/asset" --retries 2 --delay 0 --connect-timeout 10 --max-time 15
  assert_success
  grep -Fx -- '-I' "${BATS_TEST_TMPDIR}/curl.args"
  grep -Fx -- '--connect-timeout' "${BATS_TEST_TMPDIR}/curl.args"
  grep -Fx -- '10' "${BATS_TEST_TMPDIR}/curl.args"
  grep -Fx -- '--max-time' "${BATS_TEST_TMPDIR}/curl.args"
  grep -Fx -- '15' "${BATS_TEST_TMPDIR}/curl.args"
  assert_output --partial "Probing 'https://example.com/asset'"
}

@test "net__fetch_url_file atomically creates the destination parent and file" {
  reload_lib
  _NET__FETCH_TOOL=curl
  _NET__CA_CERTS_OK=true
  curl() { _net_test__curl_success "$@"; }
  export -f curl _net_test__curl_success
  local _dest="${BATS_TEST_TMPDIR}/new/nested/dir/out.bin"
  run net__fetch_url_file "https://example.com" "$_dest"
  assert_success
  assert [ -d "${BATS_TEST_TMPDIR}/new/nested/dir" ]
  assert [ "$(cat "$_dest")" = data ]
}

@test "net__fetch_url_file stages the payload beside the destination, not in TMPDIR" {
  reload_lib
  _NET__FETCH_TOOL=curl
  _NET__CA_CERTS_OK=true
  # Record the path curl is told to write to (-o). The staged payload must be a
  # sibling of the destination so the final replace is a same-filesystem atomic
  # rename and large downloads never transit a possibly-smaller $TMPDIR.
  local _opath="${BATS_TEST_TMPDIR}/opath"
  export _opath
  curl() {
    local _o=''
    while [ $# -gt 0 ]; do
      case "$1" in
        -o)
          _o="$2"
          shift 2
          ;;
        -D | -w) shift 2 ;;
        *) shift ;;
      esac
    done
    printf '%s' "$_o" > "$_opath"
    printf 'data' > "$_o"
    printf '200'
  }
  export -f curl
  local _destdir="${BATS_TEST_TMPDIR}/dest"
  local _dest="${_destdir}/out.bin"
  umask 022
  run net__fetch_url_file "https://example.com/a" "$_dest" --retries 1 --delay 0
  assert_success
  assert [ "$(cat "$_dest")" = data ]
  assert [ "$(dirname "$(cat "$_opath")")" = "$_destdir" ]
  # The staging file comes from mktemp (0600); the download must still land with
  # the umask-derived mode a direct `curl -o` produced (0644 under umask 022),
  # not silently tightened to 0600.
  assert [ "$(stat -c '%a' "$_dest")" = 644 ]
}

@test "net__fetch_url_file retries an ambiguous curl exit 35 TLS handshake failure" {
  reload_lib
  _NET__FETCH_TOOL=curl
  _NET__CA_CERTS_OK=true
  local _counter="${BATS_TEST_TMPDIR}/curl.attempts"
  printf '0' > "$_counter"
  curl() {
    local _output='' _headers='' _write_out='' _arg _n
    while [ $# -gt 0 ]; do
      _arg="$1"
      case "$_arg" in
        -o)
          _output="$2"
          shift 2
          ;;
        -D)
          _headers="$2"
          shift 2
          ;;
        -w)
          _write_out="$2"
          shift 2
          ;;
        *) shift ;;
      esac
    done
    _n=$(($(cat "$_counter") + 1))
    printf '%s' "$_n" > "$_counter"
    if [ "$_n" -eq 1 ]; then
      printf 'partial' > "$_output"
      printf 'curl: (35) SSL connect error: handshake failure\n' >&2
      [ "$_write_out" = '%{http_code}' ] && printf '000'
      return 35
    fi
    printf 'recovered' > "$_output"
    printf 'HTTP/1.1 200 OK\r\n\r\n' > "$_headers"
    [ "$_write_out" = '%{http_code}' ] && printf '200'
  }
  export -f curl
  local _dest="${BATS_TEST_TMPDIR}/download.bin"
  run net__fetch_url_file "https://example.com/asset" "$_dest" --retries 2 --delay 0
  assert_success
  assert [ "$(cat "$_dest")" = recovered ]
  assert [ "$(cat "$_counter")" -eq 2 ]
  assert_output --partial "retrying in 0s"
}

@test "net__fetch_url_stdout retries an unlisted transient HTTP 520 using capped Retry-After" {
  reload_lib
  _NET__FETCH_TOOL=curl
  _NET__CA_CERTS_OK=true
  local _counter="${BATS_TEST_TMPDIR}/curl.attempts"
  printf '0' > "$_counter"
  curl() {
    local _output='' _headers='' _write_out='' _arg _n
    while [ $# -gt 0 ]; do
      _arg="$1"
      case "$_arg" in
        -o)
          _output="$2"
          shift 2
          ;;
        -D)
          _headers="$2"
          shift 2
          ;;
        -w)
          _write_out="$2"
          shift 2
          ;;
        *) shift ;;
      esac
    done
    _n=$(($(cat "$_counter") + 1))
    printf '%s' "$_n" > "$_counter"
    if [ "$_n" -eq 1 ]; then
      printf 'HTTP/1.1 520 Unknown Error\r\nRetry-After: 600\r\n\r\n' > "$_headers"
      [ "$_write_out" = '%{http_code}' ] && printf '520'
      return 22
    fi
    printf 'available' > "$_output"
    printf 'HTTP/1.1 200 OK\r\n\r\n' > "$_headers"
    [ "$_write_out" = '%{http_code}' ] && printf '200'
  }
  export -f curl
  export DEVFEATS_NET_FETCH_MAX_DELAY=1
  sleep() { printf '%s' "$1" > "${BATS_TEST_TMPDIR}/sleep"; }
  export -f sleep
  run net__fetch_url_stdout "https://example.com/api" --retries 2 --delay 60
  assert_success
  assert_output --partial 'available'
  assert [ "$(cat "$_counter")" -eq 2 ]
  assert [ "$(cat "${BATS_TEST_TMPDIR}/sleep")" -eq 1 ]
}

@test "net__fetch_url_file does not retry a certainly persistent curl 401" {
  reload_lib
  _NET__FETCH_TOOL=curl
  _NET__CA_CERTS_OK=true
  local _counter="${BATS_TEST_TMPDIR}/curl.attempts"
  printf '0' > "$_counter"
  curl() {
    local _output='' _headers='' _write_out='' _arg
    while [ $# -gt 0 ]; do
      _arg="$1"
      case "$_arg" in
        -o)
          _output="$2"
          shift 2
          ;;
        -D)
          _headers="$2"
          shift 2
          ;;
        -w)
          _write_out="$2"
          shift 2
          ;;
        *) shift ;;
      esac
    done
    printf '1' > "$_counter"
    printf 'HTTP/1.1 401 Unauthorized\r\n\r\n' > "$_headers"
    [ "$_write_out" = '%{http_code}' ] && printf '401'
    return 22
  }
  export -f curl
  local _dest="${BATS_TEST_TMPDIR}/unauthorized"
  printf 'existing' > "$_dest"
  run net__fetch_url_file "https://example.com/unauthorized" "$_dest" --retries 3 --delay 0
  assert_failure
  assert [ "$(cat "$_counter")" -eq 1 ]
  assert [ "$(cat "$_dest")" = existing ]
  assert_output --partial 'status 401'
}

@test "net__fetch_url_file does not retry a certificate failure with curl exit 35" {
  reload_lib
  _NET__FETCH_TOOL=curl
  _NET__CA_CERTS_OK=true
  local _counter="${BATS_TEST_TMPDIR}/curl.attempts"
  printf '0' > "$_counter"
  curl() {
    local _output='' _headers='' _write_out='' _arg
    while [ $# -gt 0 ]; do
      _arg="$1"
      case "$_arg" in
        -o)
          _output="$2"
          shift 2
          ;;
        -D)
          _headers="$2"
          shift 2
          ;;
        -w)
          _write_out="$2"
          shift 2
          ;;
        *) shift ;;
      esac
    done
    printf '1' > "$_counter"
    printf 'curl: (35) SSL certificate problem: unable to get local issuer certificate\n' >&2
    [ "$_write_out" = '%{http_code}' ] && printf '000'
    return 35
  }
  export -f curl
  run net__fetch_url_file "https://example.com/cert" "${BATS_TEST_TMPDIR}/cert" --retries 3 --delay 0
  assert_failure
  assert [ "$(cat "$_counter")" -eq 1 ]
  assert_output --partial 'exit 35'
}

@test "net__fetch_url_file retries GNU and BusyBox wget failures, including an uncertain 404" {
  reload_lib
  _NET__FETCH_TOOL=wget
  _NET__CA_CERTS_OK=true
  local _counter="${BATS_TEST_TMPDIR}/wget.attempts"
  printf '0' > "$_counter"
  wget() {
    local _output='' _arg _n
    while [ $# -gt 0 ]; do
      _arg="$1"
      case "$_arg" in
        -O)
          _output="$2"
          shift 2
          ;;
        *) shift ;;
      esac
    done
    _n=$(($(cat "$_counter") + 1))
    printf '%s' "$_n" > "$_counter"
    if [ "$_n" -eq 1 ]; then
      # BusyBox wget reports network failures as generic exit 1 (unlike GNU
      # wget's documented exit 4). The lack of an HTTP status is the only
      # portable signal available to distinguish it from a permanent response.
      printf "wget: can't connect to remote host: Connection refused\n" >&2
      return 1
    fi
    printf 'recovered' > "$_output"
    printf '  HTTP/1.1 200 OK\n' >&2
  }
  export -f wget
  local _dest="${BATS_TEST_TMPDIR}/wget.bin"
  run net__fetch_url_file "https://example.com/wget" "$_dest" --retries 2 --delay 0
  assert_success
  assert [ "$(cat "$_dest")" = recovered ]
  assert [ "$(cat "$_counter")" -eq 2 ]

  printf '0' > "$_counter"
  wget() {
    local _output='' _arg _n
    while [ $# -gt 0 ]; do
      _arg="$1"
      case "$_arg" in
        -O)
          _output="$2"
          shift 2
          ;;
        *) shift ;;
      esac
    done
    _n=$(($(cat "$_counter") + 1))
    printf '%s' "$_n" > "$_counter"
    if [ "$_n" -eq 1 ]; then
      printf '  HTTP/1.1 404 Not Found\n' >&2
      return 8
    fi
    printf 'published' > "$_output"
    printf '  HTTP/1.1 200 OK\n' >&2
  }
  export -f wget
  local _missing_dest="${BATS_TEST_TMPDIR}/wget-missing"
  run net__fetch_url_file "https://example.com/wget-missing" "$_missing_dest" --retries 3 --delay 0
  assert_success
  assert [ "$(cat "$_counter")" -eq 2 ]
  assert [ "$(cat "$_missing_dest")" = published ]
}

@test "net__fetch_url_file rejects a terminal HTTP redirect and preserves its destination" {
  reload_lib
  _NET__FETCH_TOOL=curl
  _NET__CA_CERTS_OK=true
  curl() {
    local _headers='' _write_out='' _arg
    while [ $# -gt 0 ]; do
      _arg="$1"
      case "$_arg" in
        -D)
          _headers="$2"
          shift 2
          ;;
        -w)
          _write_out="$2"
          shift 2
          ;;
        *) shift ;;
      esac
    done
    printf 'HTTP/1.1 302 Found\r\n\r\n' > "$_headers"
    [ "$_write_out" = '%{http_code}' ] && printf '302'
  }
  export -f curl
  local _dest="${BATS_TEST_TMPDIR}/redirect"
  printf 'existing' > "$_dest"

  run net__fetch_url_file "https://example.com/redirect" "$_dest" --retries 2 --delay 0
  assert_failure
  assert [ "$(cat "$_dest")" = existing ]
  assert_output --partial 'attempt 1/2'
  assert_output --partial 'status 302'
}

@test "_net__fetch__retry_after_seconds parses curl (-D) and wget (-S) headers" {
  reload_lib
  # curl dumps unindented headers via -D; wget prints them via -S indented with
  # two leading spaces. Both must yield the Retry-After value, or the wget path
  # silently ignores server backoff hints.
  local _curl="${BATS_TEST_TMPDIR}/curl-headers"
  local _wget="${BATS_TEST_TMPDIR}/wget-headers"
  printf 'HTTP/1.1 503 Service Unavailable\r\nRetry-After: 30\r\nContent-Length: 0\r\n' > "$_curl"
  printf '  HTTP/1.1 503 Service Unavailable\n  Retry-After: 42\n  Content-Length: 0\n' > "$_wget"
  run _net__fetch__retry_after_seconds "$_curl"
  assert_success
  assert_output "30"
  run _net__fetch__retry_after_seconds "$_wget"
  assert_success
  assert_output "42"
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
