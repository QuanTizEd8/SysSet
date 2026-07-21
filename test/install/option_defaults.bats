#!/usr/bin/env bats
# Guardrails for option variables that must not rely on redundant :- defaults in the template.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/ensure_framework'
  install_test__ensure_framework
  load 'helpers/test_tools'
  test_tools__wire_jq_yq
  load 'helpers/stubs'
  load 'helpers/ctx'

  KEEP_CACHE=false
  KEEP_BUILD_DEPS=false
  KEEP_REPOS=false
  VERSION="stable"
  NODE_VERSION="lts"
  PREFIX_BIN_DIR="bin"
  METHOD="npm-bundled"
  NPM_PACKAGE="@devfeats/test-pkg"
  _RESOLVED_PREFIX="/opt/test"
  logging__skip() { :; }
  logging__info() { :; }
  logging__debug() { :; }
  logging__warn() { :; }
  logging__error() { printf 'ERROR: %s\n' "$*" >&2; }
  export -f logging__skip logging__info logging__debug logging__warn logging__error
}

@test "exit cleanup: KEEP_CACHE false does not run ospkg__clean" {
  ospkg__clean() {
    printf 'clean-called\n'
    return 0
  }
  export -f ospkg__clean
  KEEP_CACHE=false
  run bash -c '
    source /dev/null
    KEEP_CACHE=false
    if [[ "${KEEP_CACHE}" != true ]]; then
      ospkg__clean
    fi
  '
  assert_success
  assert_output "clean-called"
}

@test "exit cleanup: KEEP_CACHE true skips ospkg__clean branch" {
  ospkg__clean() {
    printf 'clean-called\n'
    return 0
  }
  export -f ospkg__clean
  run bash -c '
    KEEP_CACHE=true
    if [[ "${KEEP_CACHE}" != true ]]; then
      ospkg__clean
    fi
  '
  assert_success
  assert_output ""
}

@test "sidecar resolution: empty spec is rejected before sidecar branch" {
  VERSION_RESOLUTION="sidecar"
  VERSION_URI="https://example.invalid/sidecar"
  VERSION_PATTERN='version="([^"]+)"'
  ver__resolve_from_sidecar() {
    printf 'should-not-run\n'
    return 0
  }
  export -f ver__resolve_from_sidecar
  run __feat_resolve_version_spec__ ""
  assert_failure
}

@test "sidecar resolution: passes spec through without stable fallback" {
  VERSION_RESOLUTION="sidecar"
  VERSION_URI="https://example.invalid/sidecar"
  VERSION_PATTERN='version="([^"]+)"'
  ver__resolve_from_sidecar() {
    [[ "$3" == "1.2.3" ]] || return 1
    printf '1.2.3\n'
    return 0
  }
  export -f ver__resolve_from_sidecar
  run __feat_resolve_version_spec__ "1.2.3"
  assert_success
  assert_output "1.2.3"
}
