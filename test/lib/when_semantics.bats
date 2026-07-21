#!/usr/bin/env bats
# Cross-check bash ctx__match_* and jq ctx-match when semantics.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/ctx'
  load 'helpers/test_tools'
  reload_lib
  test_tools__wire_jq_yq
}

_when_jq_matches() {
  local _yaml="$1"
  local _result
  _result="$(ctx_test__jq_when "${_yaml}" 2> /dev/null || echo false)"
  [[ "${_result}" == "true" ]]
}

@test "when_vectors: bash/jq parity from fixture" {
  local _log="${BATS_TEST_TMPDIR}/when_vectors.log"
  ctx_test__run_when_vectors > "${_log}" 2>&1 || {
    cat "${_log}" >&2
    return 1
  }
}

@test "when semantics: platform AND matches in bash and jq" {
  ctx_test__reset
  ctx_test__seed_plat kernel=linux machine_release=amd64 pm=apt
  ctx_test__seed_os id=ubuntu
  run ctx__match_spec $'plat.kernel: linux\nos.id: ubuntu'
  assert_success
  _when_jq_matches $'plat.kernel: linux\nos.id: ubuntu'
}

@test "when semantics: feat.version lte (bash + jq)" {
  ctx_test__reset
  ctx_test__seed_feat version=12.1.2
  run ctx__match_spec $'feat.version:\n  lte: "12.1.2"'
  assert_success
  _when_jq_matches $'feat.version:\n  lte: "12.1.2"'
}

@test "when semantics: OR groups — second group matches" {
  ctx_test__reset
  ctx_test__seed_plat kernel=darwin machine_release=arm64 pm=brew
  ctx_test__seed_os id=macos
  run ctx__match_when $'- plat.machine_release: amd64\n- plat.kernel: darwin'
  assert_success
  _when_jq_matches $'- plat.machine_release: amd64\n- plat.kernel: darwin'
}

@test "when semantics: ne+array exclude-set (bash + jq)" {
  ctx_test__reset
  ctx_test__seed_plat pm=apt
  local _yaml=$'plat.pm:\n  ne:\n  - dnf\n  - yum'
  run ctx__match_when "${_yaml}"
  assert_success
  _when_jq_matches "${_yaml}"
  ctx_test__seed_plat pm=dnf
  run ctx__match_when "${_yaml}"
  assert_failure
  [[ "$(ctx_test__jq_when "${_yaml}" 2> /dev/null || echo false)" == false ]]
}

@test "when semantics: multi-op AND range (bash + jq)" {
  ctx_test__reset
  ctx_test__seed_feat version=1.5.0
  local _yaml=$'feat.version:\n  gte: "1.0.0"\n  lt: "2.0.0"'
  run ctx__match_when "${_yaml}"
  assert_success
  _when_jq_matches "${_yaml}"
}

@test "when semantics: eq+ne mix on same key (bash + jq)" {
  ctx_test__reset
  ctx_test__seed_plat pm=apt
  local _yaml=$'plat.pm:\n  eq:\n  - apt\n  - apk\n  ne: dnf'
  run ctx__match_when "${_yaml}"
  assert_success
  _when_jq_matches "${_yaml}"
  ctx_test__seed_plat pm=dnf
  run ctx__match_when "${_yaml}"
  assert_failure
  [[ "$(ctx_test__jq_when "${_yaml}" 2> /dev/null || echo false)" == false ]]
}

@test "when semantics: prerelease ordering (bash + jq)" {
  ctx_test__reset
  ctx_test__seed_feat version=1.0.0-rc1
  local _yaml=$'feat.version:\n  lt: "1.0.0"'
  run ctx__match_when "${_yaml}"
  assert_success
  _when_jq_matches "${_yaml}"
}

@test "when semantics: ordering fail-closed on non-semver value (bash + jq)" {
  ctx_test__reset
  ctx_test__seed_feat version=stable
  local _yaml=$'feat.version:\n  gte: "1.0"'
  run ctx__match_when "${_yaml}"
  assert_failure
  [[ "$(ctx_test__jq_when "${_yaml}" 2> /dev/null || echo false)" == false ]]
}

@test "when semantics: os.id_like token match (bash + jq)" {
  ctx_test__reset
  ctx_test__seed_os id_like="rhel centos fedora"
  local _yaml=$'os.id_like: rhel'
  run ctx__match_when "${_yaml}"
  assert_success
  _when_jq_matches "${_yaml}"
}

@test "when semantics: os.id_like ordering op always false (bash + jq)" {
  ctx_test__reset
  ctx_test__seed_os id_like="rhel centos fedora"
  local _yaml=$'os.id_like:\n  gte: rhel'
  run ctx__match_when "${_yaml}"
  assert_failure
  [[ "$(ctx_test__jq_when "${_yaml}" 2> /dev/null || echo false)" == false ]]
}

@test "when semantics: impossible AND never matches (bash + jq)" {
  ctx_test__reset
  ctx_test__seed_plat kernel=linux
  ctx_test__seed_plat pm=apt
  local _yaml=$'plat.kernel: linux\nplat.pm: apk'
  run ctx__match_when "${_yaml}"
  assert_failure
  [[ "$(ctx_test__jq_when "${_yaml}" 2> /dev/null || echo false)" == false ]]
}

@test "when semantics: empty string when matches (bash)" {
  ctx_test__reset
  run ctx__match_when ""
  assert_success
}

@test "when semantics: null YAML when matches (jq)" {
  # The jq evaluator maps null → true (when_matches: if . == null then true).
  ctx_test__reset
  local _null_json="null"
  local _ctx_json _result
  _ctx_json="$(ctx__json)"
  _result="$(json__query -L "${LIB_ROOT}" \
    --argjson ctx "${_ctx_json}" --argjson when "${_null_json}" \
    -n -f "${LIB_ROOT}/ctx-when-eval.jq" 2> /dev/null || echo false)"
  [[ "${_result}" == "true" ]]
}
