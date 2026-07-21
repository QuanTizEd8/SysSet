#!/usr/bin/env bats
# Integration tests for lib/github.bash — exercises real GitHub API calls.
#
# All github.bash functions are tested in unit tests only with canned JSON
# responses from stubbed net__fetch_url_stdout. These tests confirm the
# real API interaction works end-to-end.
#
# Uses jqlang/jq as a stable test subject with a predictable release history.
# jq uses jq-N.N.N tag format (not v*).
# GITHUB_TOKEN is passed to integration containers and provides 5000 req/hr.

bats_require_minimum_version 1.5.0

_GITHUB_TEST_REPO="jqlang/jq"

setup() {
  load '../helpers/common'
  load '../helpers/test_tools'
  reload_lib
  test_tools__wire_jq
  lib_test__network_bounded
}

@test "github__latest_tag: returns a tag for a known repo" {
  run github__latest_tag "$_GITHUB_TEST_REPO"
  assert_success
  [[ -n "$output" ]]
}

@test "github__release_tags: returns a non-empty list of tags" {
  run github__release_tags "$_GITHUB_TEST_REPO"
  assert_success
  [[ -n "$output" ]]
}

@test "github__fetch_release_json: returns JSON with tag_name field" {
  local _json
  _json="$(github__fetch_release_json "$_GITHUB_TEST_REPO")"
  run json__query -r '.tag_name' <<< "$_json"
  assert_success
  [[ -n "$output" ]]
}

@test "github__release_json_tag_name: extracts tag from release JSON file" {
  local _file="${BATS_TEST_TMPDIR}/release.json"
  github__fetch_release_json "$_GITHUB_TEST_REPO" > "$_file"
  run github__release_json_tag_name "$_file"
  assert_success
  [[ -n "$output" ]]
}

# ── github__resolve_version ───────────────────────────────────────────────────
# By default (no flags) the function prints TWO lines: full tag then bare
# version.  With --tag it prints only the full tag; with --version only the
# bare version (leading non-numeric prefix stripped).

@test "github__resolve_version: default output is two lines (tag + bare version)" {
  run github__resolve_version "$_GITHUB_TEST_REPO" "latest"
  assert_success
  local _lines
  mapfile -t _lines <<< "$output"
  [[ "${#_lines[@]}" -eq 2 ]]
  # Line 1 is the full tag (e.g. "jq-1.8.2"), line 2 the bare version ("1.8.2").
  [[ -n "${_lines[0]}" ]]
  [[ -n "${_lines[1]}" ]]
  # The bare version must not contain the jq- prefix.
  [[ "${_lines[1]}" != jq-* ]]
  # Both must contain a digit somewhere.
  [[ "${_lines[0]}" =~ [0-9] ]]
  [[ "${_lines[1]}" =~ [0-9] ]]
}

@test "github__resolve_version --tag: prints only the full tag (one line)" {
  run github__resolve_version "$_GITHUB_TEST_REPO" "latest" --tag
  assert_success
  local _lines
  mapfile -t _lines <<< "$output"
  [[ "${#_lines[@]}" -eq 1 ]]
  [[ -n "${_lines[0]}" ]]
}

@test "github__resolve_version --version: prints only the bare version (one line, no prefix)" {
  run github__resolve_version "$_GITHUB_TEST_REPO" "latest" --version
  assert_success
  local _lines
  mapfile -t _lines <<< "$output"
  [[ "${#_lines[@]}" -eq 1 ]]
  [[ -n "${_lines[0]}" ]]
  # Bare version has no leading non-numeric prefix.
  [[ "${_lines[0]}" != jq-* ]]
  [[ "${_lines[0]}" =~ ^[0-9] ]]
}

@test "github__resolve_version --tag and --version together: both lines printed" {
  # When both flags are given (or neither), two lines are output.
  run github__resolve_version "$_GITHUB_TEST_REPO" "latest" --tag --version
  assert_success
  local _lines
  mapfile -t _lines <<< "$output"
  [[ "${#_lines[@]}" -eq 2 ]]
}

# ── github__release_asset_urls ────────────────────────────────────────────────

@test "github__release_asset_urls: returns non-empty URL list for a resolved tag" {
  # Use --tag to get a single-line tag suitable for --tag argument.
  local _tag
  _tag="$(github__resolve_version "$_GITHUB_TEST_REPO" "latest" --tag)"
  run github__release_asset_urls "$_GITHUB_TEST_REPO" --tag "$_tag"
  assert_success
  [[ -n "$output" ]]
  grep -q 'https://' <<< "$output"
}
