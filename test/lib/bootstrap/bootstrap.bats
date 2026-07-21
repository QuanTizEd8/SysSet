#!/usr/bin/env bats
# Dedicated bootstrap tests for lib/bootstrap.bash — exercises installation paths.
#
# This file runs only in each logical platform's fresh bare bootstrap profile,
# separate from prepared ordinary lean/integration tests. Individual base images
# can still contain some tools; stronger absent-to-installed preconditions are a
# follow-up hardening step, so these tests currently assert successful outcomes.

bats_require_minimum_version 1.5.0

setup() {
  load '../helpers/common'
  reload_lib
  _FILE__SESSION_ROOT="${BATS_TEST_TMPDIR}/session"
  _FILE__SESSION_OWNED=false
  mkdir -p "$_FILE__SESSION_ROOT"
  export _FILE__SESSION_ROOT _FILE__SESSION_OWNED
}

teardown() {
  ospkg__cleanup_all_build_groups 2> /dev/null || true
}

# ── ospkg-based bootstraps ────────────────────────────────────────────────────

@test "bootstrap__curl: installs curl and makes it available" {
  run bootstrap__curl
  assert_success
  command -v curl > /dev/null 2>&1
}

@test "bootstrap__ca_certs: ensures CA bundle is present" {
  run bootstrap__ca_certs
  assert_success
}

@test "bootstrap__gpg: installs gpg and makes it available" {
  run bootstrap__gpg
  assert_success
  command -v gpg > /dev/null 2>&1
}

@test "bootstrap__shadow_utils: returns 0; groupadd/useradd available on Linux" {
  # --skip-darwin makes this return 0 on macOS (tool not applicable).
  run bootstrap__shadow_utils
  assert_success
  [[ "$(uname)" != Linux ]] || command -v groupadd > /dev/null 2>&1
  [[ "$(uname)" != Linux ]] || command -v useradd > /dev/null 2>&1
}

@test "bootstrap__git: installs git and makes it available" {
  run bootstrap__git
  assert_success
  command -v git > /dev/null 2>&1
}

@test "bootstrap__getent: returns 0; getent available on Linux" {
  # --skip-darwin makes this return 0 on macOS (tool not applicable).
  run bootstrap__getent
  assert_success
  [[ "$(uname)" != Linux ]] || command -v getent > /dev/null 2>&1
}

@test "bootstrap__unzip: installs unzip and makes it available" {
  run bootstrap__unzip
  assert_success
  command -v unzip > /dev/null 2>&1
}

@test "bootstrap__xz: installs xz and makes it available" {
  run bootstrap__xz
  assert_success
  command -v xz > /dev/null 2>&1
}

@test "bootstrap__bzip2: installs bzip2 and makes it available" {
  run bootstrap__bzip2
  assert_success
  command -v bzip2 > /dev/null 2>&1
}

@test "bootstrap__npm: installs npm and makes it available" {
  run bootstrap__npm
  assert_success
  command -v npm > /dev/null 2>&1
}

@test "bootstrap__sha256sum: ensures sha256sum or shasum is available" {
  run bootstrap__sha256sum
  assert_success
  command -v sha256sum > /dev/null 2>&1 || command -v shasum > /dev/null 2>&1
}

@test "bootstrap__gzip: ensures gzip is available (installing if absent)" {
  run bootstrap__gzip
  assert_success
  command -v gzip > /dev/null 2>&1
}

@test "bootstrap__tar: ensures tar is available (installing if absent)" {
  run bootstrap__tar
  assert_success
  command -v tar > /dev/null 2>&1
}

@test "bootstrap__find: installs find and makes it available" {
  run bootstrap__find
  assert_success
  command -v find > /dev/null 2>&1
}

# ── binary-download-based bootstraps ─────────────────────────────────────────

@test "bootstrap__jq: downloads jq binary and makes it available on PATH" {
  # Unlike bootstrap__yq/oras (which print their install path for the caller to
  # invoke directly), bootstrap__jq is consumed as a bare `jq` command
  # (json__query runs `jq "$@"`), so it prepends its private install dir to PATH
  # *in the calling process* and prints nothing. It must therefore be called
  # in-process here — not via `run`, whose PATH export would die with the
  # subshell — for the resulting jq to be observable on PATH.
  bootstrap__jq || fail "bootstrap__jq returned non-zero"
  command -v jq > /dev/null 2>&1
}

@test "bootstrap__yq: downloads yq binary and makes it available" {
  local _path
  _path="$(bootstrap__yq)"
  [[ -n "$_path" && -x "$_path" ]]
  run "$_path" --version
  assert_success
}

@test "bootstrap__oras: downloads oras binary, verifies GPG, and makes it available" {
  local _path
  _path="$(bootstrap__oras)"
  [[ -n "$_path" && -x "$_path" ]]
  run "$_path" version
  assert_success
}

@test "bootstrap__jsonschema: installs an absent compatible binary" {
  _BOOTSTRAP__JSONSCHEMA_BIN=""
  command() {
    if [[ "${1:-}" == -v && "${2:-}" == jsonschema ]]; then
      return 1
    fi
    builtin command "$@"
  }
  export -f command

  local _path
  _path="$(bootstrap__jsonschema)"
  [[ -n "$_path" && -f "$_path" && -x "$_path" && ! -L "$_path" ]]
  run "$_path" version
  assert_success
  [[ "$output" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}
