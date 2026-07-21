#!/usr/bin/env bats
# Unit tests for VERSION_INPUT capture and ctx sync lifecycle.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/ensure_framework'
  install_test__ensure_framework
  load 'helpers/test_tools'
  test_tools__wire_jq_yq
  load 'helpers/stubs'
  load 'helpers/ctx'
  load 'helpers/capture'

  VERSION="stable"
  VERSION_RESOLUTION="github_release"
  METHOD="package"
  ctx__reset
  _CTX__REGISTRY_INITIALIZED=true
  logging__error() { :; }
  logging__debug() { :; }
  logging__warn() { :; }
  logging__fatal() {
    printf 'FATAL: %s\n' "$*" >&2
    exit 1
  }
}

_stub_auto_method() {
  _FEAT_CONTRACT_METHODS="upstream-package package"
  _FEAT_CONTRACT_UPSTREAM_PKG_WHEN='os.id: ubuntu'
  _FEAT_CONTRACT_PACKAGE_WHEN='plat.pm: apt'
  _STUB_KERNEL="${1:-linux}"
  _STUB_ARCH="${2:-amd64}"
  _STUB_PM="${3:-apt}"
  _STUB_PRIV="${4:-privileged}"
  _STUB_PLATFORM="${5:-ubuntu}"

  os__release_kernel() { printf '%s\n' "${_STUB_KERNEL}"; }
  os__release_arch() { printf '%s\n' "${_STUB_ARCH}"; }
  os__platform() { printf '%s\n' "${_STUB_PLATFORM}"; }
  os__rust_triple() { return 1; }
  ctx__set "plat.kernel=${_STUB_KERNEL}"
  ctx__set "plat.machine_release=${_STUB_ARCH}"
  ctx__set "plat.pm=${_STUB_PM}"
  ctx__set "os.id=${_STUB_PLATFORM}"
  ospkg__has_available_version() { return 0; }
  users__is_privileged() { return 0; }
  export -f os__release_kernel os__release_arch os__platform os__rust_triple
  export -f ospkg__has_available_version users__is_privileged
}

run_auto_method() {
  local _preserve_input=false _saved_input=""
  if [[ -v VERSION_INPUT ]]; then
    _preserve_input=true
    _saved_input="${VERSION_INPUT}"
  fi
  install_test__capture_version_input
  if [[ "${_preserve_input}" == true ]]; then
    declare -g VERSION_INPUT="${_saved_input}"
  fi
  __ctx_sync_version__
  __ctx_sync_method__
  run __resolve_auto_method__
}

@test "capture: VERSION_INPUT mirrors VERSION when set" {
  VERSION="1.2.3"
  install_test__capture_version_input
  [[ "${VERSION_INPUT}" == "1.2.3" ]]
}

@test "capture: VERSION_INPUT unset when VERSION unset" {
  unset VERSION
  install_test__capture_version_input
  [[ ! -v VERSION_INPUT ]]
}

@test "capture: empty VERSION yields empty VERSION_INPUT" {
  VERSION=""
  install_test__capture_version_input
  [[ -v VERSION_INPUT ]]
  [[ "${VERSION_INPUT}" == "" ]]
}

@test "ctx sync after capture: feat.version_input before resolution" {
  VERSION="stable"
  install_test__capture_version_input
  __ctx_sync_version__
  [[ "$(ctx__get feat.version_input)" == "stable" ]]
  [[ "$(ctx__get feat.version)" == "stable" ]]
}

@test "ctx sync does not publish feat.pm_version early" {
  VERSION="beta"
  VERSION_RESOLUTION="npm"
  install_test__capture_version_input
  __ctx_sync__
  [[ "$(ctx__get feat.pm_version 2> /dev/null || true)" == "" ]]
  VERSION="2.0.0-beta.1"
  __ctx_sync_pm_version__
  [[ "$(ctx__get feat.pm_version)" == "2.0.0-beta.1" ]]
}

@test "resolution preserves VERSION_INPUT" {
  VERSION="stable"
  VERSION_RESOLUTION="github_release"
  VERSION_URI="https://api.github.com/repos/example/example"
  METHOD="binary"
  install_test__capture_version_input
  github__resolve_version() {
    printf 'v2.47.0\n2.47.0\n'
    return 0
  }
  __resolve_input_version__
  [[ "${VERSION}" == "2.47.0" ]]
  [[ "${VERSION_INPUT}" == "stable" ]]
}

@test "cargo resolution dispatches to cargo__resolve_version_uri and preserves VERSION_INPUT" {
  VERSION="stable"
  VERSION_RESOLUTION="cargo"
  VERSION_URI="https://crates.io/api/v1/crates/ripgrep"
  METHOD="binary"
  install_test__capture_version_input
  cargo__resolve_version_uri() {
    printf '13.0.0\n'
    return 0
  }
  __resolve_input_version__
  [[ "${VERSION}" == "13.0.0" ]]
  [[ "${VERSION_INPUT}" == "stable" ]]
}

@test "auto method uses VERSION_INPUT not resolved VERSION" {
  VERSION="2.47.0"
  VERSION_RESOLUTION="github_release"
  install_test__capture_version_input
  VERSION_INPUT="stable"
  _stub_auto_method
  run_auto_method
  assert_success
  assert_output "upstream-package"
}

@test "channel helper: empty VERSION_INPUT → stable" {
  VERSION_INPUT=""
  run __feat_auto_method_version_channel__
  assert_success
  assert_output "stable"
}

@test "auto method dies without VERSION_INPUT on channel check" {
  unset VERSION_INPUT
  VERSION_RESOLUTION="github_release"
  _FEAT_CONTRACT_METHODS="upstream-package package"
  _FEAT_CONTRACT_UPSTREAM_PKG_WHEN='os.id: ubuntu'
  _stub_auto_method
  run __resolve_auto_method__
  assert_failure
}
