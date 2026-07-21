#!/usr/bin/env bats
# Install init ordering: version resolution runs before method auto-selection.

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
  METHOD="auto"
  VERSION_RESOLUTION="github_release"
  _FEAT_CONTRACT_METHODS="binary package"
  _FEAT_CONTRACT_BINARY_WHEN=$'plat.machine_release: amd64\nfeat.version:\n  lte: "12.1.2"'
  _FEAT_CONTRACT_PACKAGE_WHEN='plat.pm: apt'
  _OSPKG__FAMILY=""
  _OSPKG__DETECTED=false
  _stub linux amd64 apt privileged debian
}

_stub() {
  _STUB_KERNEL="${1:-linux}"
  _STUB_ARCH="${2:-amd64}"
  _STUB_PM="${3:-apt}"
  _STUB_PRIV="${4:-privileged}"
  _STUB_PLATFORM="${5:-debian}"

  os__release_kernel() { printf '%s\n' "${_STUB_KERNEL}"; }
  os__release_arch() { printf '%s\n' "${_STUB_ARCH}"; }
  os__platform() { printf '%s\n' "${_STUB_PLATFORM}"; }
  os__rust_triple() { return 1; }
  ctx__reset
  ctx__set "plat.kernel=${_STUB_KERNEL}"
  ctx__set "plat.machine_release=${_STUB_ARCH}"
  ctx__set "plat.pm=${_STUB_PM}"
  ctx__set "os.id=${_STUB_PLATFORM}"
  _CTX__REGISTRY_INITIALIZED=true
  ospkg__has_available_version() { return 0; }
  logging__error() { printf 'ERROR: %s\n' "$*" >&2; }
  logging__debug() { :; }

  if [[ "${_STUB_PRIV}" == "privileged" ]]; then
    users__is_privileged() { return 0; }
  else
    users__is_privileged() { return 1; }
  fi
  export -f os__release_kernel os__release_arch os__platform os__rust_triple
  export -f ospkg__has_available_version logging__error logging__debug
  export -f users__is_privileged
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

@test "init order: resolved VERSION enables semver when during METHOD=auto" {
  VERSION="12.1.2"
  run_auto_method
  assert_success
  assert_output "binary"
}

@test "init order: unresolved channel VERSION fails semver when during METHOD=auto" {
  VERSION="stable"
  run_auto_method
  assert_success
  assert_output "package"
}

@test "init order: VERSION_INPUT preserved after resolution for upstream-package channel check" {
  VERSION="stable"
  VERSION_RESOLUTION="github_release"
  VERSION_URI="https://api.github.com/repos/git/git"
  _FEAT_CONTRACT_METHODS="upstream-package package"
  _FEAT_CONTRACT_UPSTREAM_PKG_WHEN='os.id: ubuntu'
  _stub linux amd64 apt privileged ubuntu
  github__resolve_version() {
    printf 'v2.47.0\n2.47.0\n'
    return 0
  }
  install_test__capture_version_input
  __resolve_input_version__
  [[ "${VERSION}" == "2.47.0" ]]
  [[ "${VERSION_INPUT}" == "stable" ]]
  run_auto_method
  assert_success
  assert_output "upstream-package"
}

@test "init order: ctx publishes preserved VERSION_INPUT after resolution" {
  VERSION="stable"
  VERSION_RESOLUTION="github_release"
  VERSION_URI="https://api.github.com/repos/git/git"
  github__resolve_version() {
    printf 'v2.47.0\n2.47.0\n'
    return 0
  }
  install_test__capture_version_input
  __resolve_input_version__
  [[ "$(ctx__get feat.version)" == "2.47.0" ]]
  [[ "$(ctx__get feat.version_input)" == "stable" ]]
}

@test "init order: feat.pm_version empty after stable resolve and package method" {
  VERSION="stable"
  VERSION_RESOLUTION="github_release"
  VERSION_URI="https://api.github.com/repos/git/git"
  METHOD="package"
  github__resolve_version() {
    printf 'v2.54.0\n2.54.0\n'
    return 0
  }
  install_test__capture_version_input
  __resolve_input_version__
  __resolve_input_method__
  __ctx_sync_pm_version__
  [[ "$(ctx__get feat.pm_version)" == "" ]]
}

@test "init order: feat.method published after method resolution" {
  METHOD="auto"
  _FEAT_CONTRACT_METHODS="binary package"
  _FEAT_CONTRACT_BINARY_WHEN=$'plat.machine_release: amd64'
  VERSION="1.0.0"
  __ctx_sync_version__
  __resolve_input_method__
  [[ "$(ctx__get feat.method)" == "binary" ]]
}

@test "init order: feat.method published after concrete method (no auto-resolution)" {
  METHOD="package"
  __ctx_sync_method__
  [[ "$(ctx__get feat.method)" == "package" ]]
}

@test "init order: feat.tag published as empty string when resolution has no tag" {
  VERSION="1.0.0"
  VERSION_RESOLUTION="none"
  _FEAT_RESOLVED_TAG=""
  __resolve_input_version__
  [[ "$(ctx__get feat.tag)" == "" ]]
}

@test "init order: feat.tag published from GitHub resolution" {
  VERSION="stable"
  VERSION_RESOLUTION="github_release"
  VERSION_URI="https://api.github.com/repos/jqlang/jq"
  github__resolve_version() {
    printf 'jq-1.8.1\n1.8.1\n'
    return 0
  }
  __resolve_input_version__
  [[ "$(ctx__get feat.tag)" == "jq-1.8.1" ]]
  [[ "$(ctx__get feat.version)" == "1.8.1" ]]
}

@test "init order: feat.tag preserved after prefix resolution without early prefix" {
  VERSION="1.8.1"
  METHOD="binary"
  VERSION_RESOLUTION="github_release"
  VERSION_URI="https://api.github.com/repos/jqlang/jq"
  PREFIX=("/usr/local")
  github__resolve_version() {
    printf 'jq-1.8.1\n1.8.1\n'
    return 0
  }
  users__get_current() { printf 'root\n'; }
  users__expand_path() { printf '%s\n' "${@: -1}"; }
  users__first_writeable_path() { printf '/usr/local\n'; }
  users__can_write() { return 0; }
  users__is_user_path() {
    printf 'system\n'
    return 0
  }
  logging__skip() { :; }
  logging__info() { :; }
  logging__debug() { :; }
  logging__fatal() { exit 1; }

  install_test__capture_version_input
  __resolve_input_version__
  __resolve_input_method__
  __resolve_input_prefixes__

  [[ "$(ctx__get feat.tag)" == "jq-1.8.1" ]]
  [[ "$(ctx__get feat.version)" == "1.8.1" ]]
  [[ "$(ctx__get feat.version_input)" == "1.8.1" ]]
  [[ "$(ctx__get feat.prefix)" == "/usr/local" ]]
  [[ "$(ctx__get feat.method)" == "binary" ]]
}

@test "resolve prefix: fails when PREFIX option is empty" {
  declare -g -a PREFIX=()
  users__get_current() { printf 'root\n'; }
  logging__fatal() { :; }

  set +e
  (__resolve_prefix__)
  local _rc=$?
  set -e
  [[ "$_rc" -eq 1 ]]
}
