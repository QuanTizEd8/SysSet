#!/usr/bin/env bats
# Unit tests for lib/posix.sh

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  reload_lib
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
