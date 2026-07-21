#!/usr/bin/env bats
# Unit tests for lib/sys_req.bash

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
  load 'helpers/ctx'
  load 'helpers/test_tools'
  reload_lib
  test_tools__wire_jq_yq
  ctx_test__reset
}

# ---------------------------------------------------------------------------
# sys_req__require_platform
# ---------------------------------------------------------------------------

@test "sys_req__require_platform: succeeds when first spec group matches" {
  ctx_test__seed_os id=debian
  run sys_req__require_platform $'os.id: debian'
  assert_success
}

@test "sys_req__require_platform: succeeds when second spec group matches" {
  ctx_test__seed_os id=ubuntu
  run sys_req__require_platform $'os.id: debian' $'os.id: ubuntu'
  assert_success
}

@test "sys_req__require_platform: fails when no spec group matches" {
  ctx_test__reset
  ctx_test__seed_os id=alpine
  run --separate-stderr sys_req__require_platform $'os.id: debian'
  assert_failure
  [[ "${stderr}" =~ "os.id: debian" ]]
}

@test "sys_req__require_platform: error message lists all groups" {
  ctx_test__reset
  ctx_test__seed_os id=alpine
  run --separate-stderr sys_req__require_platform $'os.id: debian' $'os.id: ubuntu'
  assert_failure
  [[ "${stderr}" =~ "os.id: debian" ]]
  [[ "${stderr}" =~ "os.id: ubuntu" ]]
}

@test "sys_req__require_platform: AND logic within a group" {
  ctx_test__seed_os id=debian
  ctx_test__seed_plat machine_release=amd64
  run sys_req__require_platform $'os.id: debian\nplat.machine_release: amd64'
  assert_success
}

@test "sys_req__require_platform: stops at first matching group" {
  local _calls=0
  ctx__match_spec() {
    ((_calls++)) || true
    [[ "$1" == $'os.id: debian' ]]
  }
  export -f ctx__match_spec
  sys_req__require_platform $'os.id: debian' $'os.id: ubuntu'
  [ "${_calls}" -eq 1 ]
}

# ---------------------------------------------------------------------------
# sys_req__require_root — unconditional
# ---------------------------------------------------------------------------

@test "sys_req__require_root: succeeds when privileged (no args)" {
  users__is_privileged() { return 0; }
  export -f users__is_privileged
  run sys_req__require_root
  assert_success
}

@test "sys_req__require_root: fails when not privileged (no args)" {
  users__is_privileged() { return 1; }
  export -f users__is_privileged
  run --separate-stderr sys_req__require_root
  assert_failure
  [[ "${stderr}" =~ "root" ]]
}

# ---------------------------------------------------------------------------
# sys_req__require_root — conditional (with spec groups)
# ---------------------------------------------------------------------------

@test "sys_req__require_root: succeeds when platform matches and privileged" {
  ctx_test__seed_os id=debian
  users__is_privileged() { return 0; }
  export -f users__is_privileged
  run sys_req__require_root $'os.id: debian'
  assert_success
}

@test "sys_req__require_root: fails when platform matches and not privileged" {
  ctx_test__seed_os id=debian
  users__is_privileged() { return 1; }
  export -f users__is_privileged
  run --separate-stderr sys_req__require_root $'os.id: debian'
  assert_failure
  [[ "${stderr}" =~ "root" ]]
}

@test "sys_req__require_root: succeeds when platform does not match even if not privileged" {
  ctx_test__seed_os id=ubuntu
  users__is_privileged() { return 1; }
  export -f users__is_privileged
  run sys_req__require_root $'os.id: debian'
  assert_success
}

@test "sys_req__require_root: succeeds when second spec group matches and privileged" {
  ctx_test__seed_os id=ubuntu
  users__is_privileged() { return 0; }
  export -f users__is_privileged
  run sys_req__require_root $'os.id: debian' $'os.id: ubuntu'
  assert_success
}

@test "sys_req__require_root: fails when second spec group matches and not privileged" {
  ctx_test__seed_os id=ubuntu
  users__is_privileged() { return 1; }
  export -f users__is_privileged
  run sys_req__require_root $'os.id: debian' $'os.id: ubuntu'
  assert_failure
}
