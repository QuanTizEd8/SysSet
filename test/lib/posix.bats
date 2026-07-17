#!/usr/bin/env bats
# Unit tests for lib/posix.sh

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
  reload_lib
}

# ---------------------------------------------------------------------------
# posix__run_with_retry
# ---------------------------------------------------------------------------

@test "posix__run_with_retry retries a transient package-manager failure" {
  local _attempts="${BATS_TEST_TMPDIR}/attempts"
  printf '0' > "$_attempts"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '%s\n' \
    '#!/bin/sh' \
    'n=$(($(cat "${_attempts}") + 1))' \
    'printf "%s" "$n" > "${_attempts}"' \
    'if [ "$n" -eq 1 ]; then' \
    '  printf "%s\n" "Could not resolve host: packages.example.com" >&2' \
    '  exit 1' \
    'fi' > "${BATS_TEST_TMPDIR}/bin/pm"
  chmod +x "${BATS_TEST_TMPDIR}/bin/pm"
  prepend_fake_bin_path
  export _attempts DEVFEATS_OSPKG_RETRIES=2 DEVFEATS_OSPKG_RETRY_DELAY=0

  run posix__run_with_retry apt-get install pm
  assert_success
  assert [ "$(cat "$_attempts")" -eq 2 ]
}

@test "posix__run_with_retry retries an uncertain package-manager failure" {
  local _attempts="${BATS_TEST_TMPDIR}/attempts"
  printf '0' > "$_attempts"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '%s\n' \
    '#!/bin/sh' \
    'n=$(($(cat "${_attempts}") + 1))' \
    'printf "%s" "$n" > "${_attempts}"' \
    'printf "%s\n" "E: Unable to locate package definitely-not-a-package" >&2' \
    'exit 100' > "${BATS_TEST_TMPDIR}/bin/pm"
  chmod +x "${BATS_TEST_TMPDIR}/bin/pm"
  prepend_fake_bin_path
  export _attempts DEVFEATS_OSPKG_RETRIES=3 DEVFEATS_OSPKG_RETRY_DELAY=0

  run posix__run_with_retry apt-get install pm
  assert_failure
  assert [ "$(cat "$_attempts")" -eq 3 ]
}

@test "posix__run_with_retry retries an exit-zero repository failure reported on stdout" {
  local _attempts="${BATS_TEST_TMPDIR}/attempts"
  printf '0' > "$_attempts"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '%s\n' \
    '#!/bin/sh' \
    'n=$(($(cat "${_attempts}") + 1))' \
    'printf "%s" "$n" > "${_attempts}"' \
    'if [ "$n" -eq 1 ]; then' \
    '  printf "%s\n" "Err:1 http://repo.example.invalid stable InRelease"' \
    '  printf "%s\n" "W: Failed to fetch http://repo.example.invalid/InRelease: Connection refused" >&2' \
    'fi' > "${BATS_TEST_TMPDIR}/bin/pm"
  chmod +x "${BATS_TEST_TMPDIR}/bin/pm"
  prepend_fake_bin_path
  export _attempts DEVFEATS_OSPKG_RETRIES=2 DEVFEATS_OSPKG_RETRY_DELAY=0

  run posix__run_with_retry apt-get update pm
  assert_success
  assert [ "$(cat "$_attempts")" -eq 2 ]
}

@test "posix__run_with_retry fails fast only for a proven local source configuration error" {
  local _attempts="${BATS_TEST_TMPDIR}/attempts"
  printf '0' > "$_attempts"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '%s\n' \
    '#!/bin/sh' \
    'n=$(($(cat "${_attempts}") + 1))' \
    'printf "%s" "$n" > "${_attempts}"' \
    'printf "%s\n" "E: Malformed line 1 in source list /etc/apt/sources.list" >&2' \
    'exit 100' > "${BATS_TEST_TMPDIR}/bin/pm"
  chmod +x "${BATS_TEST_TMPDIR}/bin/pm"
  prepend_fake_bin_path
  export _attempts DEVFEATS_OSPKG_RETRIES=3 DEVFEATS_OSPKG_RETRY_DELAY=0

  run posix__run_with_retry apt-get update pm
  assert_failure
  assert [ "$(cat "$_attempts")" -eq 1 ]
}

# ---------------------------------------------------------------------------
# posix__quote
# ---------------------------------------------------------------------------

@test "posix__quote: round-trips arbitrary strings through sh -c" {
  local _cases=(
    "simple"
    "with 'single' quotes"
    $'multi\nline'
    'with $(command) substitution attempt'
    'with `backticks`'
    'trailing quote'"'"
    "'leading quote"
    "'''many quotes'''"
    ""
  )
  local _c
  for _c in "${_cases[@]}"; do
    local _quoted
    _quoted="$(posix__quote "$_c")"
    local _roundtrip
    _roundtrip="$(sh -c "printf '%s' $_quoted")"
    [[ "$_roundtrip" == "$_c" ]]
  done
}

@test "posix__quote: round-trips through dash specifically" {
  command -v dash > /dev/null 2>&1 || skip "dash not installed"
  local _c="a 'quoted' \$(value) with \`backticks\` and \\backslashes\\"
  local _quoted
  _quoted="$(posix__quote "$_c")"
  local _roundtrip
  _roundtrip="$(dash -c "printf '%s' $_quoted")"
  [[ "$_roundtrip" == "$_c" ]]
}

@test "posix__quote: output is safe to eval directly" {
  local _quoted
  _quoted="$(posix__quote "it's a test")"
  local _result
  eval "_result=$_quoted"
  [[ "$_result" == "it's a test" ]]
}

@test "posix__quote: works when sourced under plain POSIX sh (dash)" {
  command -v dash > /dev/null 2>&1 || skip "dash not installed"
  run dash -c '
    . "'"${LIB_ROOT}"'/posix.sh"
    q=$(posix__quote "hello '"'"'world'"'"'")
    eval "printf %s $q"
  '
  assert_success
  assert_output "hello 'world'"
}

@test "_posix__fetch_url_file retries a transient curl failure atomically" {
  local _attempts="${BATS_TEST_TMPDIR}/attempts" _dest="${BATS_TEST_TMPDIR}/payload"
  printf '0' > "$_attempts"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  cat > "${BATS_TEST_TMPDIR}/bin/curl" << 'EOF'
#!/bin/sh
set -eu
out=
counter=${_attempts}
n=$(cat "$counter")
n=$((n + 1))
printf '%s' "$n" > "$counter"
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) out=$2; shift 2 ;;
    -D) shift 2 ;;
    -w) shift 2 ;;
    *) shift ;;
  esac
done
if [ "$n" -eq 1 ]; then
  printf '%s\n' 'Recv failure: Connection reset by peer' >&2
  exit 35
fi
printf '%s\n' 'payload' > "$out"
printf '200'
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/curl"
  prepend_fake_bin_path
  export _attempts DEVFEATS_NET_FETCH_RETRIES=2 DEVFEATS_NET_FETCH_DELAY=0

  run _posix__fetch_url_file "https://example.com/bash.tar.gz" "$_dest"
  assert_success
  assert [ "$(cat "$_attempts")" -eq 2 ]
  assert [ "$(cat "$_dest")" = payload ]
}

@test "_posix__fetch_url_file does not retry a certainly persistent HTTP failure" {
  local _attempts="${BATS_TEST_TMPDIR}/attempts" _dest="${BATS_TEST_TMPDIR}/payload"
  printf '0' > "$_attempts"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  cat > "${BATS_TEST_TMPDIR}/bin/curl" << 'EOF'
#!/bin/sh
set -eu
printf '%s' "$(($(cat "${_attempts}") + 1))" > "${_attempts}"
printf '401'
exit 22
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/curl"
  prepend_fake_bin_path
  export _attempts DEVFEATS_NET_FETCH_RETRIES=3 DEVFEATS_NET_FETCH_DELAY=0

  run _posix__fetch_url_file "https://example.com/unauthorized.tar.gz" "$_dest"
  assert_failure
  assert [ "$(cat "$_attempts")" -eq 1 ]
  [[ ! -e "$_dest" ]]
}

@test "_posix__fetch_retryable retries an unlisted HTTP failure but rejects 401" {
  local _stderr="${BATS_TEST_TMPDIR}/stderr"
  : > "$_stderr"

  run _posix__fetch_retryable 22 520 curl "$_stderr"
  assert_success

  run _posix__fetch_retryable 35 000 curl "$_stderr"
  assert_success

  run _posix__fetch_retryable 22 401 curl "$_stderr"
  assert_failure
}

@test "_posix__fetch_url_file retries a BusyBox wget network failure" {
  local _attempts="${BATS_TEST_TMPDIR}/attempts" _dest="${BATS_TEST_TMPDIR}/payload"
  printf '0' > "$_attempts"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  cat > "${BATS_TEST_TMPDIR}/bin/wget" << 'EOF'
#!/bin/sh
set -eu
out=
n=$(($(cat "${_attempts}") + 1))
printf '%s' "$n" > "${_attempts}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    -O) out=$2; shift 2 ;;
    *) shift ;;
  esac
done
if [ "$n" -eq 1 ]; then
  printf "%s\n" "wget: can't connect to remote host: Connection refused" >&2
  exit 1
fi
printf '%s\n' 'payload' > "$out"
printf '%s\n' '  HTTP/1.1 200 OK' >&2
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/wget"
  prepend_fake_bin_path
  command() {
    if [ "${1-}" = -v ] && [ "${2-}" = curl ]; then
      return 1
    fi
    builtin command "$@"
  }
  export _attempts
  export -f command
  export DEVFEATS_NET_FETCH_RETRIES=2 DEVFEATS_NET_FETCH_DELAY=0

  run _posix__fetch_url_file "https://example.com/bash.tar.gz" "$_dest"
  assert_success
  assert [ "$(cat "$_attempts")" -eq 2 ]
  assert [ "$(cat "$_dest")" = payload ]
}
