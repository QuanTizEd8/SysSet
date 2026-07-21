#!/usr/bin/env bats
# Integration tests for lib/net.bash — exercises real HTTP downloads.
#
# Unit tests verify curl/wget dispatch using stubs. These tests confirm
# that actual network connectivity works end-to-end.

bats_require_minimum_version 1.5.0

setup() {
  load '../helpers/common'
  reload_lib
  lib_test__network_bounded
}

@test "net__fetch_url_stdout: downloads a small public URL to stdout" {
  # api.github.com/zen returns a short Zen of GitHub string.
  # Pass GITHUB_TOKEN when available — macOS CI runners hit API rate limits otherwise.
  local -a _args=()
  [[ -z "${GITHUB_TOKEN:-}" ]] || _args+=(--header "Authorization: token $GITHUB_TOKEN")
  run net__fetch_url_stdout "https://api.github.com/zen" "${_args[@]}"
  assert_success
  [[ -n "$output" ]]
}

@test "net__fetch_url_file: downloads a small public URL to a file" {
  local -a _args=()
  [[ -z "${GITHUB_TOKEN:-}" ]] || _args+=(--header "Authorization: token $GITHUB_TOKEN")
  local _dest="${BATS_TEST_TMPDIR}/zen.txt"
  run net__fetch_url_file "https://api.github.com/zen" "$_dest" "${_args[@]}"
  assert_success
  [[ -f "$_dest" && -s "$_dest" ]]
}

@test "net__fetch_url_stdout: returns failure for an unreachable host" {
  lib_test__net_fetch_fail_fast
  run net__fetch_url_stdout "https://0.0.0.0/no"
  assert_failure
}

@test "net__fetch_url_file: returns failure for an unreachable host" {
  lib_test__net_fetch_fail_fast
  local _dest="${BATS_TEST_TMPDIR}/unreachable.txt"
  run net__fetch_url_file "https://0.0.0.0/no" "$_dest"
  assert_failure
}
