#!/usr/bin/env bats
# Integration tests for lib/cargo.bash — exercises real crates.io API calls.
#
# cargo.bash functions are otherwise tested in unit tests with canned JSON from
# a stubbed _cargo__registry_get. These tests confirm the real API interaction
# works end-to-end, including the User-Agent header that crates.io requires
# (it returns HTTP 403 for requests without one).
#
# Uses BurntSushi/ripgrep as a stable test subject: its 13.x series contains a
# single release (13.0.0), which makes prefix resolution deterministic.

bats_require_minimum_version 1.5.0

_CARGO_TEST_URI="https://crates.io/api/v1/crates/ripgrep"

setup() {
  load '../helpers/common'
  load '../helpers/test_tools'
  reload_lib
  test_tools__wire_jq
  lib_test__network_bounded
}

@test "cargo__resolve_version_uri (real): exact prefix '13' resolves to 13.0.0" {
  run cargo__resolve_version_uri "$_CARGO_TEST_URI" "13"
  assert_success
  assert_output "13.0.0"
}

@test "cargo__resolve_version_uri (real): exact version '13.0.0' resolves to itself" {
  run cargo__resolve_version_uri "$_CARGO_TEST_URI" "13.0.0"
  assert_success
  assert_output "13.0.0"
}

@test "cargo__resolve_version_uri (real): stable resolves to a final semver" {
  run cargo__resolve_version_uri "$_CARGO_TEST_URI" "stable"
  assert_success
  [[ -n "$output" ]]
  # A final release: numeric core, no pre-release suffix.
  [[ "$output" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "cargo__resolve_version_uri (real): latest resolves to a non-empty version" {
  run cargo__resolve_version_uri "$_CARGO_TEST_URI" "latest"
  assert_success
  [[ -n "$output" ]]
  [[ "$output" =~ ^[0-9] ]]
}

@test "cargo__resolve_version_uri (real): default spec resolves to a final semver" {
  run cargo__resolve_version_uri "$_CARGO_TEST_URI"
  assert_success
  [[ "$output" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}
