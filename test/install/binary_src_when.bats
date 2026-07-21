#!/usr/bin/env bats
# Unit tests for __feat_filter_binary_src__ in the install framework.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/ensure_framework'
  install_test__ensure_framework
  load 'helpers/test_tools'
  test_tools__wire_jq_yq
  load 'helpers/stubs'
  load 'helpers/ctx'
  load 'helpers/capture'

  VERSION="12.1.2"
  METHOD="binary"
  _FEAT_RESOLVED_TAG="v12.1.2"
  BINARY_SRC=()
  ctx__reset
  ctx__set feat.version=12.1.2
  ctx__set feat.version_input=12.1.2
  ctx__set feat.tag=v12.1.2
  ctx__set feat.method=binary
  _CTX__REGISTRY_INITIALIZED=true
}

_publish_feat_ctx() {
  install_test__capture_version_input
  ctx__set feat.version="${VERSION}"
  ctx__set feat.version_input="${VERSION_INPUT}"
  ctx__set feat.tag="${_FEAT_RESOLVED_TAG:-}"
  ctx__set feat.method="${METHOD:-binary}"
}

@test "__feat_filter_binary_src__: plain path passes through" {
  BINARY_SRC=("tokei")
  run __feat_filter_binary_src__
  assert_success
  assert_output "tokei"
}

@test "__feat_filter_binary_src__: tab-when line included when condition matches" {
  local _when=$'feat.version:\n  lte: "12.1.2"'
  BINARY_SRC=("tokei	${_when}")
  run __feat_filter_binary_src__
  assert_success
  assert_output "tokei"
}

@test "__feat_filter_binary_src__: tab-when line excluded when condition fails" {
  VERSION="14.0.0"
  _publish_feat_ctx
  local _when=$'feat.version:\n  lte: "12.1.2"'
  BINARY_SRC=("tokei	${_when}")
  run __feat_filter_binary_src__
  assert_success
  assert_output ""
}

@test "__feat_filter_binary_src__: all conditional lines filtered returns empty" {
  VERSION="14.0.0"
  _publish_feat_ctx
  local _when=$'feat.version:\n  lte: "12.1.2"'
  BINARY_SRC=("tokei	${_when}")
  run __feat_filter_binary_src__
  assert_success
  assert_output ""
}

@test "__install_run_binary__: fails when all binary_src entries filtered out" {
  VERSION="14.0.0"
  _publish_feat_ctx
  local _when=$'feat.version:\n  lte: "12.1.2"'
  BINARY_SRC=("tokei	${_when}")
  BINARY_ASSET_URI="https://example.com/tokei.tar.gz"
  _RESOLVED_PREFIX="/usr/local"
  run __install_run_binary__
  assert_failure
  assert_output --partial "No binary_src entries matched"
}

@test "__feat_filter_binary_src__: mixed plain and conditional lines" {
  BINARY_SRC=("always" $'old\tfeat.version:\n  lte: "12.1.2"')
  run __feat_filter_binary_src__
  assert_success
  assert_output $'always\nold'
}

@test "__feat_filter_binary_src__: platform condition includes on matching kernel" {
  ctx__set plat.kernel=linux
  _CTX__REGISTRY_INITIALIZED=true
  BINARY_SRC=($'tokei-linux\tplat.kernel: linux' $'tokei-darwin\tplat.kernel: darwin')
  run __feat_filter_binary_src__
  assert_success
  assert_output "tokei-linux"
}

@test "__feat_filter_binary_src__: platform condition excludes on non-matching kernel" {
  ctx__set plat.kernel=darwin
  _CTX__REGISTRY_INITIALIZED=true
  BINARY_SRC=($'tokei-linux\tplat.kernel: linux')
  run __feat_filter_binary_src__
  assert_success
  assert_output ""
}

@test "__feat_filter_binary_src__: OR-array when includes matching entry" {
  ctx__set plat.machine_release=arm64
  _CTX__REGISTRY_INITIALIZED=true
  local _yaml=$'- plat.machine_release: amd64\n- plat.machine_release: arm64'
  BINARY_SRC=("tokei	${_yaml}")
  run __feat_filter_binary_src__
  assert_success
  assert_output "tokei"
}

@test "__feat_filter_binary_src__: OR-array when excludes non-matching entry" {
  ctx__set plat.machine_release=armv7
  _CTX__REGISTRY_INITIALIZED=true
  local _yaml=$'- plat.machine_release: amd64\n- plat.machine_release: arm64'
  BINARY_SRC=("tokei	${_yaml}")
  run __feat_filter_binary_src__
  assert_success
  assert_output ""
}

@test "__feat_filter_binary_src__: combined platform and version condition" {
  ctx__set plat.machine_release=amd64
  ctx__set feat.version=1.5.0
  _CTX__REGISTRY_INITIALIZED=true
  local _yaml=$'plat.machine_release: amd64\nfeat.version:\n  gte: "1.0.0"'
  BINARY_SRC=("tokei	${_yaml}")
  run __feat_filter_binary_src__
  assert_success
  assert_output "tokei"
}
