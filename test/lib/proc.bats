#!/usr/bin/env bats
# Unit tests for lib/proc.bash

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
  load 'helpers/test_tools'
  reload_lib
  # proc__run_command_form parses its JSON argument via json__query → jq. The
  # bash -c subshells below source only a minimal module subset (file/logging/
  # bootstrap/json/proc), which cannot satisfy bootstrap__jq's download-path
  # dependencies (install/github/net/os/uri). Prime the cached jq onto PATH —
  # inherited by those subshells — so bootstrap__jq short-circuits at
  # `command -v jq` and never enters that path.
  test_tools__wire_jq
}

@test "proc__run_command_form runs JSON string via sh -c" {
  run bash -c 'source "$1/file.bash" && source "$1/logging.sh" && source "$1/logging.bash" && source "$1/bootstrap.bash" && source "$1/json.bash" && source "$1/proc.bash" && printf %s "\"echo hello\"" | proc__run_command_form' _ "${LIB_ROOT}"
  assert_output "hello"
  assert_success
}

@test "proc__run_command_form runs JSON array argv" {
  run bash -c 'source "$1/file.bash" && source "$1/logging.sh" && source "$1/logging.bash" && source "$1/bootstrap.bash" && source "$1/json.bash" && source "$1/proc.bash" && printf %s "[\"/bin/sh\",\"-c\",\"echo arr\"]" | proc__run_command_form' _ "${LIB_ROOT}"
  assert_output "arr"
  assert_success
}

@test "proc__run_parallel runs labeled subshells" {
  _od="$(mktemp -d "${BATS_TEST_TMPDIR}/pp.XXXXXX")"
  run proc__run_parallel --outdir "$_od" -- "a" /bin/sh -c "echo one" -- "b" /bin/sh -c "echo two"
  assert_output --partial "one"
  assert_output --partial "two"
  assert_success
  rm -rf "$_od"
}

@test "proc__run_parallel returns non-zero when any child fails" {
  _od="$(mktemp -d "${BATS_TEST_TMPDIR}/pp2.XXXXXX")"
  run proc__run_parallel --outdir "$_od" -- "ok" /bin/sh -c "echo good" -- "bad" /bin/sh -c "exit 7"
  assert_failure
  assert_output --partial "good"
  rm -rf "$_od"
}

@test "proc__run_parallel buffers per-label output (no interleaving)" {
  _od="$(mktemp -d "${BATS_TEST_TMPDIR}/pp3.XXXXXX")"
  run proc__run_parallel --outdir "$_od" -- \
    "a" /bin/sh -c "printf 'A1\nA2\n'" -- \
    "b" /bin/sh -c "printf 'B1\nB2\n'"
  assert_success
  # The two labels' lines are concatenated, not interleaved.
  [ -f "${_od}/a.out" ]
  [ -f "${_od}/b.out" ]
  grep -q "A1" "${_od}/a.out"
  grep -q "A2" "${_od}/a.out"
  grep -q "B1" "${_od}/b.out"
  grep -q "B2" "${_od}/b.out"
  rm -rf "$_od"
}

@test "proc__run_command_form object form runs keyed commands" {
  run bash -c 'source "$1/file.bash" && source "$1/logging.sh" && source "$1/logging.bash" && source "$1/bootstrap.bash" && source "$1/json.bash" && source "$1/proc.bash" && printf %s "{\"one\":\"echo A\",\"two\":\"echo B\"}" | proc__run_command_form' _ "${LIB_ROOT}"
  assert_success
  assert_output --partial "A"
  assert_output --partial "B"
}

@test "proc__run_command_form --cwd changes working directory for string form" {
  _tmp="$(mktemp -d "${BATS_TEST_TMPDIR}/pcw.XXXXXX")"
  run bash -c 'source "$1/file.bash" && source "$1/logging.sh" && source "$1/logging.bash" && source "$1/bootstrap.bash" && source "$1/json.bash" && source "$1/proc.bash" && printf %s "\"pwd\"" | proc__run_command_form --cwd "$2"' _ "${LIB_ROOT}" "$_tmp"
  assert_success
  # macOS symlinks /tmp → /private/tmp; compare realpaths.
  _got="$(cd "$output" && pwd -P)"
  _want="$(cd "$_tmp" && pwd -P)"
  [ "$_got" = "$_want" ]
  rm -rf "$_tmp"
}

@test "proc__run_command_form --cwd changes working directory for object form" {
  _tmp="$(mktemp -d "${BATS_TEST_TMPDIR}/pcwo.XXXXXX")"
  run bash -c 'source "$1/file.bash" && source "$1/logging.sh" && source "$1/logging.bash" && source "$1/bootstrap.bash" && source "$1/json.bash" && source "$1/proc.bash" && printf %s "{\"probe\":\"pwd\"}" | proc__run_command_form --cwd "$2"' _ "${LIB_ROOT}" "$_tmp"
  assert_success
  # macOS symlinks /tmp → /private/tmp; compare realpaths.
  _got="$(cd "$output" && pwd -P)"
  _want="$(cd "$_tmp" && pwd -P)"
  [ "$_got" = "$_want" ]
  rm -rf "$_tmp"
}

@test "proc__run_command_form fails on unsupported JSON types" {
  run bash -c 'source "$1/file.bash" && source "$1/logging.sh" && source "$1/logging.bash" && source "$1/bootstrap.bash" && source "$1/json.bash" && source "$1/proc.bash" && printf %s "42" | proc__run_command_form' _ "${LIB_ROOT}"
  assert_failure
}
