#!/usr/bin/env bats
# Unit tests for lib/json.sh

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
  reload_lib json.sh
}

@test "json__root_scalar_stdin prints string and numeric keys from stdin JSON" {
  run sh -c '. "$1" && printf %s "{\"tag_name\":\"v1\",\"id\":42}" | json__root_scalar_stdin tag_name' _ "${LIB_ROOT}/json.sh"
  assert_output "v1"
  assert_success
  run sh -c '. "$1" && printf %s "{\"tag_name\":\"v1\",\"id\":42}" | json__root_scalar_stdin id' _ "${LIB_ROOT}/json.sh"
  assert_output "42"
  assert_success
}

@test "json__root_scalar_stdin fails when key is missing" {
  run sh -c '. "$1" && printf %s "{\"name\":\"x\"}" | json__root_scalar_stdin tag_name' _ "${LIB_ROOT}/json.sh"
  assert_failure
}

@test "json__array_field_lines_stdin prints one line per array element field" {
  run sh -c '. "$1" && printf %s "[{\"tag_name\":\"a\"},{\"tag_name\":\"b\"}]" | json__array_field_lines_stdin tag_name' _ "${LIB_ROOT}/json.sh"
  assert_output "a
b"
  assert_success
}

@test "json__root_scalar_stdin reuses cached parser across calls in one shell" {
  run bash -ec '. "$1"; printf %s "{\"a\":1}" | json__root_scalar_stdin a; printf %s "{\"b\":2}" | json__root_scalar_stdin b' _ "${LIB_ROOT}/json.sh"
  assert_output $'1\n2'
  assert_success
}

@test "json__object_array_field_lines_stdin plucks field from nested array" {
  run sh -c '. "$1" && printf %s "{\"assets\":[{\"browser_download_url\":\"https://a.tgz\"},{\"browser_download_url\":\"https://b.zip\"}]}" | json__object_array_field_lines_stdin assets browser_download_url' _ "${LIB_ROOT}/json.sh"
  assert_output "https://a.tgz
https://b.zip"
  assert_success
}

@test "json__object_map_string_values_stdin prints string values under envs" {
  run sh -c '. "$1" && printf %s "{\"envs\":{\"base\":\"/opt/conda\",\"myenv\":\"/opt/conda/envs/my\"}}" | json__object_map_string_values_stdin envs' _ "${LIB_ROOT}/json.sh"
  assert_output "/opt/conda
/opt/conda/envs/my"
  assert_success
}

@test "json__nodejs_index_version_stdin lts-first head major exact" {
  _fixture='[{"version":"v1.0.0","lts":false},{"version":"v22.1.0","lts":true},{"version":"v22.0.0","lts":true}]'
  run sh -c '. "$1" && printf %s "$2" | json__nodejs_index_version_stdin lts-first' _ "${LIB_ROOT}/json.sh" "$_fixture"
  assert_output "v22.1.0"
  assert_success
  run sh -c '. "$1" && printf %s "$2" | json__nodejs_index_version_stdin head' _ "${LIB_ROOT}/json.sh" "$_fixture"
  assert_output "v1.0.0"
  assert_success
  run sh -c '. "$1" && printf %s "$2" | json__nodejs_index_version_stdin major 22' _ "${LIB_ROOT}/json.sh" "$_fixture"
  assert_output "v22.1.0"
  assert_success
  run sh -c '. "$1" && printf %s "$2" | json__nodejs_index_version_stdin exact v22.0.0' _ "${LIB_ROOT}/json.sh" "$_fixture"
  assert_output "v22.0.0"
  assert_success
}
