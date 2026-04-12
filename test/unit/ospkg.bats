#!/usr/bin/env bats
# Unit tests for lib/ospkg.sh

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
}

# ---------------------------------------------------------------------------
# ospkg::detect  (direct calls — checks internal state variables)
# ---------------------------------------------------------------------------

@test "ospkg::detect identifies apt-get ecosystem" {
  reload_lib ospkg.sh
  create_fake_bin "apt-get"
  create_fake_bin "uname" "Linux"
  prepend_fake_bin_path
  ospkg::detect
  [[ "$_OSPKG_PREFIX" == "apt" ]]
  [[ "$_OSPKG_PKG_MNGR" == "apt-get" ]]
  [[ "$_OSPKG_DETECTED" == true ]]
}

@test "ospkg::detect identifies apk ecosystem" {
  reload_lib ospkg.sh
  create_fake_bin "apk"
  create_fake_bin "uname" "Linux"
  PATH="${BATS_TEST_TMPDIR}/bin" ospkg::detect
  [[ "$_OSPKG_PREFIX" == "apk" ]]
  [[ "$_OSPKG_PKG_MNGR" == "apk" ]]
  [[ "$_OSPKG_DETECTED" == true ]]
}

@test "ospkg::detect identifies dnf ecosystem" {
  reload_lib ospkg.sh
  create_fake_bin "dnf"
  create_fake_bin "uname" "Linux"
  PATH="${BATS_TEST_TMPDIR}/bin" ospkg::detect
  [[ "$_OSPKG_PREFIX" == "dnf" ]]
  [[ "$_OSPKG_PKG_MNGR" == "dnf" ]]
  [[ "$_OSPKG_DETECTED" == true ]]
}

@test "ospkg::detect is idempotent when _OSPKG_DETECTED=true" {
  reload_lib ospkg.sh
  _OSPKG_DETECTED=true
  _OSPKG_PREFIX="sentinel"
  ospkg::detect
  [[ "$_OSPKG_PREFIX" == "sentinel" ]]
}

@test "ospkg::detect fails when no package manager is found" {
  reload_lib ospkg.sh
  # Override PATH to empty so no package manager binary is found.
  PATH="${BATS_TEST_TMPDIR}/bin" run ospkg::detect
  assert_failure
  assert_output --partial "No supported package manager"
}

@test "ospkg::detect identifies zypper ecosystem" {
  reload_lib ospkg.sh
  create_fake_bin "zypper"
  create_fake_bin "uname" "Linux"
  PATH="${BATS_TEST_TMPDIR}/bin" ospkg::detect
  [[ "$_OSPKG_PREFIX" == "zypper" ]]
  [[ "$_OSPKG_PKG_MNGR" == "zypper" ]]
  [[ "$_OSPKG_DETECTED" == true ]]
}

@test "ospkg::detect identifies microdnf ecosystem" {
  reload_lib ospkg.sh
  create_fake_bin "microdnf"
  create_fake_bin "uname" "Linux"
  PATH="${BATS_TEST_TMPDIR}/bin" ospkg::detect
  [[ "$_OSPKG_PREFIX" == "dnf" ]]
  [[ "$_OSPKG_PKG_MNGR" == "microdnf" ]]
  [[ "${#_OSPKG_UPDATE[@]}" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_seed_apt_context() {
  reload_lib ospkg.sh
  create_fake_bin "apt-get"
  create_fake_bin "uname" "Linux"
  prepend_fake_bin_path
  ospkg::detect
  _OSPKG_OS_RELEASE[pm]="apt"
  _OSPKG_OS_RELEASE[arch]="x86_64"
  _OSPKG_OS_RELEASE[id]="ubuntu"
  _OSPKG_OS_RELEASE[id_like]="debian"
  _OSPKG_OS_RELEASE[version_id]="22.04"
  _OSPKG_OS_RELEASE[version_codename]="jammy"
}

# ---------------------------------------------------------------------------
# ospkg::update
# ---------------------------------------------------------------------------

@test "ospkg::update rejects unknown option" {
  _seed_apt_context
  run ospkg::update --bogus
  assert_failure
  assert_output --partial "unknown option"
}

@test "ospkg::update skips when update command array is empty" {
  reload_lib ospkg.sh
  # Seed a microdnf-like context: detected, but no update command.
  create_fake_bin "microdnf"
  create_fake_bin "uname" "Linux"
  PATH="${BATS_TEST_TMPDIR}/bin" ospkg::detect
  run ospkg::update
  assert_success
  assert_output --partial "not supported"
}

@test "ospkg::update runs update command with --force" {
  _seed_apt_context
  # The fake apt-get stub exits 0 for any subcommand.
  run ospkg::update --force
  assert_success
}

# ---------------------------------------------------------------------------
# ospkg::install
# ---------------------------------------------------------------------------

@test "ospkg::install invokes the install command" {
  _seed_apt_context
  run ospkg::install curl
  assert_success
}

@test "ospkg::install skips when apt packages are already installed" {
  _seed_apt_context
  # Fake dpkg that reports the package as installed (exit 0).
  create_fake_bin "dpkg" ""
  prepend_fake_bin_path
  run ospkg::install curl
  assert_success
  assert_output --partial "already installed"
}

# ---------------------------------------------------------------------------
# ospkg::clean
# ---------------------------------------------------------------------------

@test "ospkg::clean succeeds for apt context" {
  _seed_apt_context
  # The fake apt-get stub handles 'clean' and 'dist-clean'.
  run ospkg::clean
  assert_success
}

# ---------------------------------------------------------------------------
# ospkg::detect — brew paths
# ---------------------------------------------------------------------------

@test "ospkg::detect identifies brew on macOS (Darwin)" {
  reload_lib ospkg.sh
  # Fake 'uname' returning Darwin and a fake 'brew' binary.
  create_fake_bin "uname" "Darwin"
  create_fake_bin "brew" ""
  prepend_fake_bin_path
  # 'sw_vers' must exist (macOS only command path).
  create_fake_bin "sw_vers" "14.0"
  ospkg::detect
  [[ "$_OSPKG_PREFIX" == "brew" ]]
  [[ "$_OSPKG_PKG_MNGR" == "brew" ]]
  [[ "${_OSPKG_OS_RELEASE[id]}" == "macos" ]]
}

@test "ospkg::detect selects brew when _OSPKG_PREFER_LINUXBREW=true and brew is on PATH" {
  reload_lib ospkg.sh
  create_fake_bin "uname" "Linux"
  create_fake_bin "apt-get" ""
  create_fake_bin "brew" ""
  prepend_fake_bin_path
  _OSPKG_PREFER_LINUXBREW=true
  ospkg::detect
  [[ "$_OSPKG_PREFIX" == "brew" ]]
  [[ "$_OSPKG_PKG_MNGR" == "brew" ]]
}

@test "ospkg::detect falls back to native PM when _OSPKG_PREFER_LINUXBREW=true but brew absent" {
  reload_lib ospkg.sh
  create_fake_bin "uname" "Linux"
  create_fake_bin "apt-get" ""
  # Use restricted PATH so real brew is not found.
  _OSPKG_PREFER_LINUXBREW=true
  PATH="${BATS_TEST_TMPDIR}/bin" ospkg::detect
  [[ "$_OSPKG_PREFIX" == "apt" ]]
  [[ "$_OSPKG_PKG_MNGR" == "apt-get" ]]
}

# ---------------------------------------------------------------------------
# ospkg::parse_manifest_yaml  (requires jq)
# ---------------------------------------------------------------------------

@test "ospkg::parse_manifest_yaml emits package records from plain packages list" {
  _seed_apt_context
  command -v jq > /dev/null 2>&1 || skip "jq not available"
  local _json_file
  _json_file="$(mktemp "${BATS_TEST_TMPDIR}/manifest_XXXXXX.json")"
  printf '{"packages":["curl","wget","git"]}' > "$_json_file"
  local _output
  _output="$(ospkg::parse_manifest_yaml "$_json_file")"
  rm -f "$_json_file"
  [[ "$_output" == *'"kind":"package"'* ]]
  [[ "$_output" == *'"name":"curl"'* ]]
  [[ "$_output" == *'"name":"wget"'* ]]
}

@test "ospkg::parse_manifest_yaml emits prescript record" {
  _seed_apt_context
  command -v jq > /dev/null 2>&1 || skip "jq not available"
  local _json_file
  _json_file="$(mktemp "${BATS_TEST_TMPDIR}/manifest_XXXXXX.json")"
  printf '{"prescripts":"echo hello\\n","packages":["curl"]}' > "$_json_file"
  local _output
  _output="$(ospkg::parse_manifest_yaml "$_json_file")"
  rm -f "$_json_file"
  [[ "$_output" == *'"kind":"prescript"'* ]]
}

@test "ospkg::parse_manifest_yaml filters packages with when clause" {
  _seed_apt_context
  command -v jq > /dev/null 2>&1 || skip "jq not available"
  local _json_file
  _json_file="$(mktemp "${BATS_TEST_TMPDIR}/manifest_XXXXXX.json")"
  # brew-only package should NOT appear for apt context.
  printf '{"packages":[{"name":"brew-pkg","when":"pm=brew"},{"name":"apt-pkg","when":"pm=apt"}]}' \
    > "$_json_file"
  local _output
  _output="$(ospkg::parse_manifest_yaml "$_json_file")"
  rm -f "$_json_file"
  [[ "$_output" != *'"name":"brew-pkg"'* ]]
  [[ "$_output" == *'"name":"apt-pkg"'* ]]
}

@test "ospkg::parse_manifest_yaml skips the manifest when top-level when mismatches" {
  _seed_apt_context
  command -v jq > /dev/null 2>&1 || skip "jq not available"
  local _json_file
  _json_file="$(mktemp "${BATS_TEST_TMPDIR}/manifest_XXXXXX.json")"
  printf '{"when":"pm=brew","packages":["should-not-appear"]}' > "$_json_file"
  local _output
  _output="$(ospkg::parse_manifest_yaml "$_json_file")"
  rm -f "$_json_file"
  [[ -z "$_output" ]]
}

@test "ospkg::parse_manifest_yaml emits packages from pm-specific apt block" {
  _seed_apt_context
  command -v jq > /dev/null 2>&1 || skip "jq not available"
  local _json_file
  _json_file="$(mktemp "${BATS_TEST_TMPDIR}/manifest_XXXXXX.json")"
  printf '{"apt":{"packages":["libssl-dev"]},"brew":{"packages":["openssl"]}}' > "$_json_file"
  local _output
  _output="$(ospkg::parse_manifest_yaml "$_json_file")"
  rm -f "$_json_file"
  [[ "$_output" == *'"name":"libssl-dev"'* ]]
  [[ "$_output" != *'"name":"openssl"'* ]]
}

@test "ospkg::run YAML path works on macOS (portable mktemp)" {
  [[ "$(uname -s)" == "Darwin" ]] || skip "macOS-only"
  command -v jq > /dev/null 2>&1 || skip "jq not available"
  reload_lib ospkg.sh

  # A fake yq that ignores its arguments and emits a fixed JSON manifest.
  local _fake_yq="${BATS_TEST_TMPDIR}/bin/yq"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/bin/bash\necho '"'"'{"packages":["foo"]}'"'"'\n' > "$_fake_yq"
  chmod +x "$_fake_yq"

  logging::cleanup() { return 0; }
  ospkg::detect() {
    _OSPKG_PREFIX="brew"
    _OSPKG_PKG_MNGR="brew"
    _OSPKG_DETECTED=true
    _OSPKG_OS_RELEASE[pm]="brew"
    _OSPKG_OS_RELEASE[kernel]="darwin"
    _OSPKG_OS_RELEASE[id]="macos"
    _OSPKG_OS_RELEASE[id_like]="macos"
    _OSPKG_OS_RELEASE[arch]="arm64"
    return 0
  }
  _ospkg_ensure_yq() {
    _OSPKG_YQ_BIN="${BATS_TEST_TMPDIR}/bin/yq"
    return 0
  }

  run ospkg::run --manifest $'packages:\n  - foo\n' --dry_run
  assert_success
  assert_output --partial "[dry-run] packages: foo"
}
