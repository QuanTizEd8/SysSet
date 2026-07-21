#!/usr/bin/env bats
# Unit tests for lib/argparse.bash

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
}

# ---------------------------------------------------------------------------
# argparse__validate_bool
# ---------------------------------------------------------------------------

@test "argparse__validate_bool: accepts true" {
  export MY_VAR=true
  run argparse__validate_bool MY_VAR
  assert_success
}

@test "argparse__validate_bool: accepts false" {
  export MY_VAR=false
  run argparse__validate_bool MY_VAR
  assert_success
}

@test "argparse__validate_bool: rejects other values" {
  export MY_VAR=yes
  run --separate-stderr argparse__validate_bool MY_VAR
  assert_failure
  [[ "${stderr}" =~ "my_var" ]]
  [[ "${stderr}" =~ "expected: true, false" ]]
}

@test "argparse__validate_bool: rejects empty string" {
  export MY_VAR=""
  run argparse__validate_bool MY_VAR
  assert_failure
}

# ---------------------------------------------------------------------------
# argparse__validate_enum
# ---------------------------------------------------------------------------

@test "argparse__validate_enum: accepts a valid value" {
  export MY_VAR=beta
  run argparse__validate_enum MY_VAR alpha beta gamma
  assert_success
}

@test "argparse__validate_enum: accepts first value" {
  export MY_VAR=alpha
  run argparse__validate_enum MY_VAR alpha beta gamma
  assert_success
}

@test "argparse__validate_enum: rejects an invalid value" {
  export MY_VAR=delta
  run --separate-stderr argparse__validate_enum MY_VAR alpha beta gamma
  assert_failure
  [[ "${stderr}" =~ "my_var" ]]
  [[ "${stderr}" =~ "delta" ]]
  [[ "${stderr}" =~ "alpha" ]]
}

@test "argparse__validate_enum: includes all valid values in error" {
  export MY_VAR=bad
  run --separate-stderr argparse__validate_enum MY_VAR x y z
  assert_failure
  [[ "${stderr}" =~ "x" ]]
  [[ "${stderr}" =~ "y" ]]
  [[ "${stderr}" =~ "z" ]]
}

@test "argparse__validate_enum: accepts empty string as valid value" {
  export MY_VAR=""
  run argparse__validate_enum MY_VAR "" other
  assert_success
}

# ---------------------------------------------------------------------------
# argparse__validate_enum_array
# ---------------------------------------------------------------------------

@test "argparse__validate_enum_array: accepts all valid elements" {
  declare -a MY_ARR=(alpha gamma)
  export MY_ARR
  run argparse__validate_enum_array MY_ARR alpha beta gamma
  assert_success
}

@test "argparse__validate_enum_array: accepts empty array" {
  declare -a MY_ARR=()
  export MY_ARR
  run argparse__validate_enum_array MY_ARR alpha beta
  assert_success
}

@test "argparse__validate_enum_array: rejects invalid element" {
  declare -a MY_ARR=(alpha bad)
  export MY_ARR
  run --separate-stderr argparse__validate_enum_array MY_ARR alpha beta gamma
  assert_failure
  [[ "${stderr}" =~ "bad" ]]
  [[ "${stderr}" =~ "my_arr" ]]
}

@test "argparse__validate_enum_array: reports first invalid element" {
  declare -a MY_ARR=(beta nope alpha)
  export MY_ARR
  run --separate-stderr argparse__validate_enum_array MY_ARR alpha beta
  assert_failure
  [[ "${stderr}" =~ "nope" ]]
}

# ---------------------------------------------------------------------------
# argparse__validate_integer
# ---------------------------------------------------------------------------

@test "argparse__validate_integer: accepts positive integer" {
  export MY_VAR=42
  run argparse__validate_integer MY_VAR
  assert_success
}

@test "argparse__validate_integer: accepts zero" {
  export MY_VAR=0
  run argparse__validate_integer MY_VAR
  assert_success
}

@test "argparse__validate_integer: accepts negative integer" {
  export MY_VAR=-5
  run argparse__validate_integer MY_VAR
  assert_success
}

@test "argparse__validate_integer: rejects non-integer string" {
  export MY_VAR=abc
  run --separate-stderr argparse__validate_integer MY_VAR
  assert_failure
  [[ "${stderr}" =~ "my_var" ]]
}

@test "argparse__validate_integer: rejects float" {
  export MY_VAR=3.14
  run argparse__validate_integer MY_VAR
  assert_failure
}

@test "argparse__validate_integer: rejects empty string" {
  export MY_VAR=""
  run argparse__validate_integer MY_VAR
  assert_failure
}

# ---------------------------------------------------------------------------
# argparse__validate_integer_min
# ---------------------------------------------------------------------------

@test "argparse__validate_integer_min: accepts value equal to min" {
  export MY_VAR=5
  run argparse__validate_integer_min MY_VAR 5
  assert_success
}

@test "argparse__validate_integer_min: accepts value above min" {
  export MY_VAR=10
  run argparse__validate_integer_min MY_VAR 5
  assert_success
}

@test "argparse__validate_integer_min: rejects value below min" {
  export MY_VAR=4
  run --separate-stderr argparse__validate_integer_min MY_VAR 5
  assert_failure
  [[ "${stderr}" =~ "my_var" ]]
  [[ "${stderr}" =~ ">= 5" ]]
}

# ---------------------------------------------------------------------------
# argparse__validate_integer_max
# ---------------------------------------------------------------------------

@test "argparse__validate_integer_max: accepts value equal to max" {
  export MY_VAR=10
  run argparse__validate_integer_max MY_VAR 10
  assert_success
}

@test "argparse__validate_integer_max: accepts value below max" {
  export MY_VAR=3
  run argparse__validate_integer_max MY_VAR 10
  assert_success
}

@test "argparse__validate_integer_max: rejects value above max" {
  export MY_VAR=11
  run --separate-stderr argparse__validate_integer_max MY_VAR 10
  assert_failure
  [[ "${stderr}" =~ "my_var" ]]
  [[ "${stderr}" =~ "<= 10" ]]
}

# ---------------------------------------------------------------------------
# argparse__validate_path
# ---------------------------------------------------------------------------

@test "argparse__validate_path: skips empty value" {
  export MY_VAR=""
  run argparse__validate_path MY_VAR -d
  assert_success
}

@test "argparse__validate_path: accepts existing directory for -d" {
  export MY_VAR="/tmp"
  run argparse__validate_path MY_VAR -d
  assert_success
}

@test "argparse__validate_path: rejects non-directory for -d" {
  export MY_VAR="/no/such/directory"
  run --separate-stderr argparse__validate_path MY_VAR -d
  assert_failure
  [[ "${stderr}" =~ "my_var" ]]
  [[ "${stderr}" =~ "-d" ]]
}

@test "argparse__validate_path: accepts existing file for -f" {
  local _tmpfile
  _tmpfile="$(mktemp "${BATS_TEST_TMPDIR}/argparse-file.XXXXXX")"
  export MY_VAR="${_tmpfile}"
  run argparse__validate_path MY_VAR -f
  assert_success
  rm -f "${_tmpfile}"
}

@test "argparse__validate_path: accepts existing path for -e" {
  export MY_VAR="/tmp"
  run argparse__validate_path MY_VAR -e
  assert_success
}

@test "argparse__validate_path: rejects missing path for -e" {
  export MY_VAR="/no/such/path"
  run argparse__validate_path MY_VAR -e
  assert_failure
}

@test "argparse__validate_path: rejects http URI as not-a-path" {
  export MY_VAR="https://example.com/env.yml"
  run argparse__validate_path MY_VAR -f
  assert_failure
}

# ---------------------------------------------------------------------------
# argparse__validate_path_array
# ---------------------------------------------------------------------------

@test "argparse__validate_path_array: accepts existing directories" {
  MY_ARR=("$BATS_TEST_TMPDIR")
  run argparse__validate_path_array MY_ARR -d
  assert_success
}

@test "argparse__validate_path_array: rejects missing directory" {
  MY_ARR=("/no/such/directory")
  run --separate-stderr argparse__validate_path_array MY_ARR -d
  assert_failure
  [[ "${stderr}" =~ "my_arr" ]]
}

@test "argparse__validate_path_array: rejects remote URI elements" {
  MY_ARR=("https://example.com/env.yml")
  run argparse__validate_path_array MY_ARR -f
  assert_failure
}

# ---------------------------------------------------------------------------
# argparse__split_lines
# ---------------------------------------------------------------------------

@test "argparse__split_lines: trims and drops blank lines" {
  unset MY_ARR
  argparse__split_lines MY_ARR $'/tmp/test-envs\n    \n'
  assert [ "${#MY_ARR[@]}" -eq 1 ]
  assert [ "${MY_ARR[0]}" = "/tmp/test-envs" ]
}

# ---------------------------------------------------------------------------
# argparse__default
# ---------------------------------------------------------------------------

@test "argparse__default: sets variable when unset" {
  unset MY_VAR
  argparse__default MY_VAR "hello"
  assert [ "${MY_VAR}" = "hello" ]
}

@test "argparse__default: leaves variable unchanged when already set" {
  MY_VAR="existing"
  argparse__default MY_VAR "default"
  assert [ "${MY_VAR}" = "existing" ]
}

@test "argparse__default: sets variable to empty string when default is empty" {
  unset MY_VAR
  argparse__default MY_VAR ""
  assert [ "${MY_VAR+set}" = "set" ]
  assert [ "${MY_VAR}" = "" ]
}

@test "argparse__default: treats variable set to empty as already set" {
  MY_VAR=""
  argparse__default MY_VAR "default"
  assert [ "${MY_VAR}" = "" ]
}

# ---------------------------------------------------------------------------
# argparse__var_declared
# ---------------------------------------------------------------------------

@test "argparse__var_declared: false when variable is unset" {
  unset MY_ARR
  run argparse__var_declared MY_ARR
  assert_failure
}

@test "argparse__var_declared: true for empty declared array" {
  declare -a MY_ARR=()
  run argparse__var_declared MY_ARR
  assert_success
}

@test "argparse__var_declared: true for non-empty array" {
  declare -a MY_ARR=(a)
  run argparse__var_declared MY_ARR
  assert_success
}

@test "argparse__var_declared: [[ -v ]] does not see empty declared arrays" {
  declare -a MY_ARR=()
  # Across all bash versions, [[ -v ]] treats empty indexed arrays as unset.
  # argparse__var_declared uses declare -p to correctly detect them.
  ! [[ -v MY_ARR ]]
}

# ---------------------------------------------------------------------------
# argparse__default_array
# ---------------------------------------------------------------------------

@test "argparse__default_array: sets undeclared array to empty" {
  unset MY_ARR
  argparse__default_array MY_ARR
  argparse__var_declared MY_ARR
  assert [ "${#MY_ARR[@]}" -eq 0 ]
}

@test "argparse__default_array: leaves already-declared array unchanged" {
  declare -a MY_ARR=(a b c)
  argparse__default_array MY_ARR
  assert [ "${#MY_ARR[@]}" -eq 3 ]
  assert [ "${MY_ARR[0]}" = "a" ]
}

@test "argparse__default_array: leaves empty declared array unchanged" {
  declare -a MY_ARR=()
  argparse__default_array MY_ARR
  assert [ "${#MY_ARR[@]}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# argparse__default_array_value
# ---------------------------------------------------------------------------

@test "argparse__default_array_value: sets undeclared array from multi-line value" {
  unset MY_ARR
  argparse__default_array_value MY_ARR $'line1\nline2\nline3'
  assert [ "${#MY_ARR[@]}" -eq 3 ]
  assert [ "${MY_ARR[0]}" = "line1" ]
  assert [ "${MY_ARR[1]}" = "line2" ]
  assert [ "${MY_ARR[2]}" = "line3" ]
}

@test "argparse__default_array_value: leaves already-declared array unchanged" {
  declare -a MY_ARR=(existing)
  argparse__default_array_value MY_ARR $'other\nvalue'
  assert [ "${#MY_ARR[@]}" -eq 1 ]
  assert [ "${MY_ARR[0]}" = "existing" ]
}

@test "argparse__default_array_value: skips blank lines in value" {
  unset MY_ARR
  argparse__default_array_value MY_ARR $'a\n\nb\n'
  assert [ "${#MY_ARR[@]}" -eq 2 ]
  assert [ "${MY_ARR[0]}" = "a" ]
  assert [ "${MY_ARR[1]}" = "b" ]
}

@test "argparse__default_array_value: skips whitespace-only lines" {
  unset MY_ARR
  argparse__default_array_value MY_ARR $'/tmp/test-envs\n    \n'
  assert [ "${#MY_ARR[@]}" -eq 1 ]
  assert [ "${MY_ARR[0]}" = "/tmp/test-envs" ]
}

@test "argparse__normalize_array: trims and drops whitespace-only elements" {
  MY_ARR=("  /tmp/a  " "    " "/tmp/b")
  argparse__normalize_array MY_ARR
  assert [ "${#MY_ARR[@]}" -eq 2 ]
  assert [ "${MY_ARR[0]}" = "/tmp/a" ]
  assert [ "${MY_ARR[1]}" = "/tmp/b" ]
}

# ---------------------------------------------------------------------------
# argparse__resolve_uri_options
# ---------------------------------------------------------------------------

@test "argparse__resolve_uri_options: scalar remote URI materializes and chmod applies" {
  _uri__net_fetch() { printf '#!/bin/sh\necho ok\n' > "$2"; }
  export -f _uri__net_fetch

  unset INSTALLER_DIR
  export _FEAT_ID="tfeat"
  export SCRIPT="http://stub.example/x.sh"

  argparse__resolve_uri_options $'script\tSCRIPT\tstring\t+x'
  [[ -f "$SCRIPT" ]]
  [[ -x "$SCRIPT" ]]
}

@test "argparse__resolve_uri_options: array remote URIs resolve to local paths" {
  _uri__net_fetch() { printf 'data\n' > "$2"; }
  export -f _uri__net_fetch

  unset INSTALLER_DIR
  export _FEAT_ID="tfeat"
  MY_ARR=("http://stub.example/a" "http://stub.example/b")

  argparse__resolve_uri_options $'arr\tMY_ARR\tarray\t'
  [[ -f "${MY_ARR[0]}" ]] || {
    echo "missing file: ${MY_ARR[0]}"
    return 1
  }
  [[ -f "${MY_ARR[1]}" ]] || {
    echo "missing file: ${MY_ARR[1]}"
    return 1
  }
}

@test "argparse__resolve_uri_options: uses INSTALLER_DIR when set" {
  _uri__net_fetch() { printf 'data\n' > "$2"; }
  export -f _uri__net_fetch

  export _FEAT_ID="tfeat"
  INSTALLER_DIR="${BATS_TEST_TMPDIR}/idir"
  export INSTALLER_DIR
  export ONE="http://stub.example/one"

  argparse__resolve_uri_options $'one\tONE\tstring\t'
  [[ "$ONE" == "${INSTALLER_DIR}/uri/one/"* ]] || {
    echo "ONE=$ONE"
    return 1
  }
  [[ -f "$ONE" ]]
}

@test "argparse__resolve_uri_options: multi-record spec resolves all entries" {
  _uri__net_fetch() {
    case "$1" in
      *"/a") printf 'a\n' > "$2" ;;
      *"/b") printf 'b\n' > "$2" ;;
      *"/s.sh") printf '#!/bin/sh\necho ok\n' > "$2" ;;
      *) printf 'x\n' > "$2" ;;
    esac
  }
  export -f _uri__net_fetch

  unset INSTALLER_DIR
  export _FEAT_ID="tfeat"
  MY_ARR=("http://stub.example/a" "http://stub.example/b")
  export SCRIPT="http://stub.example/s.sh"

  argparse__resolve_uri_options $'arr\tMY_ARR\tarray\t\nscript\tSCRIPT\tstring\t+x'
  [[ -f "${MY_ARR[0]}" ]]
  [[ -f "${MY_ARR[1]}" ]]
  [[ -f "${SCRIPT}" ]]
  [[ -x "${SCRIPT}" ]]
}

# ---------------------------------------------------------------------------
# argparse__resolve_content_or_uri_options
# ---------------------------------------------------------------------------

@test "argparse__resolve_content_or_uri_options: inline multi-line content materialised to file" {
  export _FEAT_ID="tfeat"
  export MANIFEST=$'packages:\n  - curl\n  - git'

  argparse__resolve_content_or_uri_options $'manifest\tMANIFEST\tstring\tfalse'

  [[ -f "$MANIFEST" ]]
  grep -q "curl" "$MANIFEST"
}

@test "argparse__resolve_content_or_uri_options: literal backslash-n normalised and materialised" {
  export _FEAT_ID="tfeat"
  # Value uses literal \n as some devcontainer CLI environments serialize it.
  export MANIFEST='packages:\n  - curl'

  argparse__resolve_content_or_uri_options $'manifest\tMANIFEST\tstring\tfalse'

  [[ -f "$MANIFEST" ]]
  grep -q "curl" "$MANIFEST"
}

@test "argparse__resolve_content_or_uri_options: existing local file passed through unchanged" {
  export _FEAT_ID="tfeat"
  local _f="${BATS_TEST_TMPDIR}/mypkg.yaml"
  printf 'packages:\n  - git\n' > "$_f"
  export MANIFEST="$_f"

  argparse__resolve_content_or_uri_options $'manifest\tMANIFEST\tstring\tfalse'

  [[ "$MANIFEST" == "$_f" ]]
  [[ -f "$MANIFEST" ]]
}

@test "argparse__resolve_content_or_uri_options: remote URI fetched and variable rewritten" {
  _uri__net_fetch() { printf 'packages:\n  - wget\n' > "$2"; }
  export -f _uri__net_fetch

  export _FEAT_ID="tfeat"
  export MANIFEST="http://stub.example/packages.yaml"

  argparse__resolve_content_or_uri_options $'manifest\tMANIFEST\tstring\tfalse'

  [[ -f "$MANIFEST" ]]
  grep -q "wget" "$MANIFEST"
}

@test "argparse__resolve_content_or_uri_options: non-existing path with allow_nonexistent passed through" {
  export _FEAT_ID="tfeat"
  export MANIFEST="/workspace/not/here.yaml"

  argparse__resolve_content_or_uri_options $'manifest\tMANIFEST\tstring\ttrue'

  [[ "$MANIFEST" == "/workspace/not/here.yaml" ]]
}

@test "argparse__resolve_content_or_uri_options: non-existing path without allow_nonexistent fails" {
  export _FEAT_ID="tfeat"
  export MANIFEST="/workspace/not/here.yaml"

  run argparse__resolve_content_or_uri_options $'manifest\tMANIFEST\tstring\tfalse'
  [[ $status -ne 0 ]]
}

@test "argparse__resolve_content_or_uri_options: empty value is a no-op" {
  export _FEAT_ID="tfeat"
  export MANIFEST=""

  argparse__resolve_content_or_uri_options $'manifest\tMANIFEST\tstring\tfalse'
  [[ -z "$MANIFEST" ]]
}

# ---------------------------------------------------------------------------
# argparse__validate_jsonschema
# ---------------------------------------------------------------------------

@test "argparse__validate_jsonschema: valid file passes" {
  local _schema="${BATS_TEST_TMPDIR}/schema.json"
  local _instance="${BATS_TEST_TMPDIR}/valid.json"
  printf '{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","properties":{"name":{"type":"string"}},"additionalProperties":false}' > "$_schema"
  printf '{"name":"hello"}' > "$_instance"

  json__validate() { return 0; }
  export -f json__validate

  export MY_FILE="$_instance"
  argparse__validate_jsonschema MY_FILE "$_schema" false
}

@test "argparse__validate_jsonschema: invalid file exits 1 with error" {
  local _schema="${BATS_TEST_TMPDIR}/schema.json"
  local _instance="${BATS_TEST_TMPDIR}/invalid.json"
  printf '{}' > "$_schema"
  printf '{}' > "$_instance"

  json__validate() { return 1; }
  export -f json__validate

  export MY_FILE="$_instance"
  run argparse__validate_jsonschema MY_FILE "$_schema" false
  [[ $status -ne 0 ]]
}

@test "argparse__validate_jsonschema: non-existing file with allow_nonexistent skips" {
  export MY_FILE="/not/here.yaml"
  argparse__validate_jsonschema MY_FILE "/any/schema.json" true
}

@test "argparse__validate_jsonschema: non-existing file without allow_nonexistent exits 1" {
  export MY_FILE="/not/here.yaml"
  run argparse__validate_jsonschema MY_FILE "/any/schema.json" false
  [[ $status -ne 0 ]]
}

@test "argparse__validate_jsonschema: empty variable is a no-op" {
  export MY_FILE=""
  argparse__validate_jsonschema MY_FILE "/any/schema.json" false
}
