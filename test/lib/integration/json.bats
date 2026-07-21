#!/usr/bin/env bats
# Integration tests for lib/json.bash — exercises real jq and sourcemeta/jsonschema.
#
# All json function tests use immutable suite-cached real binaries.

bats_require_minimum_version 1.5.0

FIXTURES_DIR="${REPO_ROOT}/test/lib/fixtures/json"

setup() {
  load '../helpers/common'
  load '../helpers/test_tools'
  reload_lib
  test_tools__wire_jq_yq_jsonschema
}

@test "json__root_scalar_stdin prints string and numeric keys from stdin JSON" {
  run bash -c '. "$1/__init__.bash" && printf %s "{\"tag_name\":\"v1\",\"id\":42}" | json__root_scalar_stdin tag_name' _ "${LIB_ROOT}"
  assert_output "v1"
  assert_success
  run bash -c '. "$1/__init__.bash" && printf %s "{\"tag_name\":\"v1\",\"id\":42}" | json__root_scalar_stdin id' _ "${LIB_ROOT}"
  assert_output "42"
  assert_success
}

@test "json__root_scalar_stdin fails when key is missing" {
  run bash -c '. "$1/__init__.bash" && printf %s "{\"name\":\"x\"}" | json__root_scalar_stdin tag_name' _ "${LIB_ROOT}"
  assert_failure
}

@test "json__array_field_lines_stdin prints one line per array element field" {
  run bash -c '. "$1/__init__.bash" && printf %s "[{\"tag_name\":\"a\"},{\"tag_name\":\"b\"}]" | json__array_field_lines_stdin tag_name' _ "${LIB_ROOT}"
  assert_output "a
b"
  assert_success
}

@test "json__root_scalar_stdin reuses cached parser across calls in one shell" {
  run bash -ec '. "$1/__init__.bash"; printf %s "{\"a\":1}" | json__root_scalar_stdin a; printf %s "{\"b\":2}" | json__root_scalar_stdin b' _ "${LIB_ROOT}"
  assert_output $'1\n2'
  assert_success
}

@test "json__object_array_field_lines_stdin plucks field from nested array" {
  run bash -c '. "$1/__init__.bash" && printf %s "{\"assets\":[{\"browser_download_url\":\"https://a.tgz\"},{\"browser_download_url\":\"https://b.zip\"}]}" | json__object_array_field_lines_stdin assets browser_download_url' _ "${LIB_ROOT}"
  assert_output "https://a.tgz
https://b.zip"
  assert_success
}

@test "json__object_map_string_values_stdin prints string values under envs" {
  run bash -c '. "$1/__init__.bash" && printf %s "{\"envs\":{\"base\":\"/opt/conda\",\"myenv\":\"/opt/conda/envs/my\"}}" | json__object_map_string_values_stdin envs' _ "${LIB_ROOT}"
  assert_output "/opt/conda
/opt/conda/envs/my"
  assert_success
}

@test "json__object_key_string_lines_stdin handles array or object of strings" {
  run bash -c '. "$1/__init__.bash" && printf %s "{\"items\":[\"/a\",\"/b\"]}" | json__object_key_string_lines_stdin items' _ "${LIB_ROOT}"
  assert_output "/a
/b"
  assert_success
  run bash -c '. "$1/__init__.bash" && printf %s "{\"items\":{\"x\":\"/a\",\"y\":\"/b\"}}" | json__object_key_string_lines_stdin items' _ "${LIB_ROOT}"
  assert_output "/a
/b"
  assert_success
}

@test "json__object_keys_stdin lists top-level keys" {
  run bash -c '. "$1/__init__.bash" && printf %s "{\"z\":1,\"a\":2}" | json__object_keys_stdin' _ "${LIB_ROOT}"
  assert_output "a
z"
  assert_success
}

@test "json__value_stdin prints compact sub-value" {
  run bash -c '. "$1/__init__.bash" && printf %s "{\"x\":[\"p\"]}" | json__value_stdin .x' _ "${LIB_ROOT}"
  assert_output '["p"]'
  assert_success
}

@test "json__coerce_scalar_stdin maps boolean to string" {
  run bash -c '. "$1/__init__.bash" && printf %s "true" | json__coerce_scalar_stdin' _ "${LIB_ROOT}"
  assert_output "true"
  assert_success
}

@test "json__coerce_scalar_stdin fails on object" {
  run bash -c '. "$1/__init__.bash" && printf %s "{}" | json__coerce_scalar_stdin' _ "${LIB_ROOT}"
  assert_failure
}

@test "json__query passes arguments through to jq" {
  run bash -c '. "$1/__init__.bash" && printf %s "{\"x\":42}" | json__query -r ".x"' _ "${LIB_ROOT}"
  assert_output "42"
  assert_success
}

@test "json__query forwards multi-arg jq filter" {
  run bash -c '. "$1/__init__.bash" && printf %s "[1,2,3]" | json__query -r ".[]"' _ "${LIB_ROOT}"
  assert_output "$(printf '1\n2\n3')"
  assert_success
}

# ---------------------------------------------------------------------------
# json__validate — JSON Schema validation via sourcemeta/jsonschema
# ---------------------------------------------------------------------------

@test "json__validate: accepts a valid JSON instance" {
  run json__validate \
    "${FIXTURES_DIR}/valid.json" \
    "${FIXTURES_DIR}/simple.schema.json"
  assert_success
}

@test "json__validate: rejects an instance with additionalProperties violation" {
  run json__validate \
    "${FIXTURES_DIR}/invalid.json" \
    "${FIXTURES_DIR}/simple.schema.json"
  assert_failure
}

@test "json__validate: error output mentions the offending field" {
  run json__validate \
    "${FIXTURES_DIR}/invalid.json" \
    "${FIXTURES_DIR}/simple.schema.json"
  assert_failure
  assert_output --partial "unknown_field"
}

@test "json__validate: fails when instance file does not exist" {
  run json__validate \
    "${BATS_TEST_TMPDIR}/nonexistent.json" \
    "${FIXTURES_DIR}/simple.schema.json"
  assert_failure
}

@test "json__validate: fails when schema file does not exist" {
  run json__validate \
    "${FIXTURES_DIR}/valid.json" \
    "${BATS_TEST_TMPDIR}/no-schema.json"
  assert_failure
}

@test "json__validate: accepts a valid ospkg manifest against ospkg schema" {
  run json__validate \
    "${FIXTURES_DIR}/valid-manifest.json" \
    "${REPO_ROOT}/features/install-os-pkg/manifest.schema.json"
  assert_success
}

@test "json__validate: rejects an invalid ospkg manifest against ospkg schema" {
  run json__validate \
    "${FIXTURES_DIR}/invalid-manifest.json" \
    "${REPO_ROOT}/features/install-os-pkg/manifest.schema.json"
  assert_failure
  # Error output should mention the violation.
  assert_output --partial "packages"
}

# ---------------------------------------------------------------------------
# json__query_multi
# ---------------------------------------------------------------------------

@test "json__query_multi: extracts fields in order, NUL-terminated" {
  run bash -c '. "$1/__init__.bash" && mapfile -d "" -t out < <(json__query_multi "{\"a\":\"1\",\"b\":\"2\",\"c\":null}" ".a" ".b" ".c // \"default\""); printf "%s\n" "${out[@]}"' _ "${LIB_ROOT}"
  assert_output "1
2
default"
}

@test "json__query_multi: serializes array/object results via tojson" {
  run bash -c '. "$1/__init__.bash" && mapfile -d "" -t out < <(json__query_multi "{\"arr\":[\"x\",\"y\"]}" ".arr"); printf "%s\n" "${out[@]}"' _ "${LIB_ROOT}"
  assert_output '["x","y"]'
}

@test "json__query_multi: does not drop a trailing empty-string field" {
  # Regression test: an earlier separator-only NUL scheme made a trailing
  # empty result indistinguishable from end-of-stream, so mapfile silently
  # dropped it. Every record must be NUL-TERMINATED, not merely separated.
  run bash -c '. "$1/__init__.bash" && mapfile -d "" -t out < <(json__query_multi "{\"a\":\"1\",\"b\":\"2\"}" ".a" ".b" ".missing // \"\""); echo "${#out[@]}"; printf "[%s]\n" "${out[@]}"' _ "${LIB_ROOT}"
  assert_output "3
[1]
[2]
[]"
}

@test "json__query_multi: preserves an explicit JSON boolean false (not the same as absent)" {
  # Regression test: the wrapper used to serialize every result via
  # `. // "" | tostring`. jq's `//` treats JSON false the same as null, so a
  # field explicitly set to false collapsed to "" — indistinguishable from a
  # missing field, and impossible for a caller's own `.field // "default"` to
  # tell apart from "absent" either (the same jq gotcha one level up).
  run bash -c '. "$1/__init__.bash" && mapfile -d "" -t out < <(json__query_multi "{\"a\":false,\"b\":true,\"c\":null}" ".a" ".b" ".c"); printf "[%s]\n" "${out[@]}"' _ "${LIB_ROOT}"
  assert_output "[false]
[true]
[]"
}

@test "json__query_multi: preserves embedded newlines within a single field" {
  run bash -c '. "$1/__init__.bash" && mapfile -d "" -t out < <(json__query_multi "{\"a\":\"line1\\nline2\",\"b\":\"plain\"}" ".a" ".b"); printf "%s|\n" "${out[@]}"' _ "${LIB_ROOT}"
  assert_output "line1
line2|
plain|"
}

# ---------------------------------------------------------------------------
# json__string_or_array_lines
# ---------------------------------------------------------------------------

@test "json__string_or_array_lines: absent field prints nothing" {
  run bash -c '. "$1/__init__.bash" && json__string_or_array_lines "{}" users' _ "${LIB_ROOT}"
  assert_output ""
}

@test "json__string_or_array_lines: string field prints one line" {
  run bash -c '. "$1/__init__.bash" && json__string_or_array_lines "{\"users\":\"all\"}" users' _ "${LIB_ROOT}"
  assert_output "all"
}

@test "json__string_or_array_lines: array field prints one line per element" {
  run bash -c '. "$1/__init__.bash" && json__string_or_array_lines "{\"users\":[\"alice\",\"bob\"]}" users' _ "${LIB_ROOT}"
  assert_output "alice
bob"
}

# ---------------------------------------------------------------------------
# json__from_yaml
# ---------------------------------------------------------------------------

@test "json__from_yaml: converts a YAML file to canonical JSON" {
  local _f="${BATS_TEST_TMPDIR}/manifest.yaml"
  printf 'files:\n  - op: create\n    dest: /tmp/x\n' > "${_f}"
  run bash -c '. "$1/__init__.bash" && json__from_yaml "$2" | jq -c .' _ "${LIB_ROOT}" "${_f}"
  assert_success
  assert_output '{"files":[{"op":"create","dest":"/tmp/x"}]}'
}

@test "json__from_yaml: passes an already-JSON file through unchanged" {
  local _f="${BATS_TEST_TMPDIR}/manifest.json"
  printf '{"a":1}' > "${_f}"
  run bash -c '. "$1/__init__.bash" && json__from_yaml "$2" | jq -c .' _ "${LIB_ROOT}" "${_f}"
  assert_success
  assert_output '{"a":1}'
}
