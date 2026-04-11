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
  prepend_fake_bin_path
  ospkg::detect
  [[ "$_OSPKG_PREFIX" == "apt" ]]
  [[ "$_OSPKG_PKG_MNGR" == "apt-get" ]]
  [[ "$_OSPKG_DETECTED" == true ]]
}

@test "ospkg::detect identifies apk ecosystem" {
  reload_lib ospkg.sh
  create_fake_bin "apk"
  prepend_fake_bin_path
  ospkg::detect
  [[ "$_OSPKG_PREFIX" == "apk" ]]
  [[ "$_OSPKG_PKG_MNGR" == "apk" ]]
  [[ "$_OSPKG_DETECTED" == true ]]
}

@test "ospkg::detect identifies dnf ecosystem" {
  reload_lib ospkg.sh
  create_fake_bin "dnf"
  prepend_fake_bin_path
  ospkg::detect
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
  prepend_fake_bin_path
  ospkg::detect
  [[ "$_OSPKG_PREFIX" == "zypper" ]]
  [[ "$_OSPKG_PKG_MNGR" == "zypper" ]]
  [[ "$_OSPKG_DETECTED" == true ]]
}

@test "ospkg::detect identifies microdnf ecosystem" {
  reload_lib ospkg.sh
  create_fake_bin "microdnf"
  prepend_fake_bin_path
  ospkg::detect
  [[ "$_OSPKG_PREFIX" == "dnf" ]]
  [[ "$_OSPKG_PKG_MNGR" == "microdnf" ]]
  [[ "${#_OSPKG_UPDATE[@]}" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# ospkg::eval_selector_block  (direct calls after seeding OS context)
# ---------------------------------------------------------------------------

_seed_apt_context() {
  reload_lib ospkg.sh
  create_fake_bin "apt-get"
  prepend_fake_bin_path
  ospkg::detect
  _OSPKG_OS_RELEASE[pm]="apt"
  _OSPKG_OS_RELEASE[arch]="x86_64"
  _OSPKG_OS_RELEASE[id]="ubuntu"
  _OSPKG_OS_RELEASE[id_like]="debian"
  _OSPKG_OS_RELEASE[version_id]="22.04"
  _OSPKG_OS_RELEASE[version_codename]="jammy"
}

@test "ospkg::eval_selector_block matches pm=apt" {
  _seed_apt_context
  ospkg::eval_selector_block "pm=apt"
}

@test "ospkg::eval_selector_block matches id=ubuntu" {
  _seed_apt_context
  ospkg::eval_selector_block "id=ubuntu"
}

@test "ospkg::eval_selector_block matches multiple conditions" {
  _seed_apt_context
  ospkg::eval_selector_block "pm=apt,arch=x86_64"
}

@test "ospkg::eval_selector_block fails when pm mismatches" {
  _seed_apt_context
  run ospkg::eval_selector_block "pm=apk"
  assert_failure
}

@test "ospkg::eval_selector_block is case-insensitive" {
  _seed_apt_context
  ospkg::eval_selector_block "id=Ubuntu"
}

# ---------------------------------------------------------------------------
# ospkg::pkg_matches_selectors  (direct calls)
# ---------------------------------------------------------------------------

@test "ospkg::pkg_matches_selectors returns true for a line with no selectors" {
  _seed_apt_context
  ospkg::pkg_matches_selectors "curl"
}

@test "ospkg::pkg_matches_selectors returns true when selector matches" {
  _seed_apt_context
  ospkg::pkg_matches_selectors "curl [pm=apt]"
}

@test "ospkg::pkg_matches_selectors returns false when selector mismatches" {
  _seed_apt_context
  run ospkg::pkg_matches_selectors "some-pkg [pm=apk]"
  assert_failure
}

@test "ospkg::pkg_matches_selectors passes when any of multiple blocks match" {
  _seed_apt_context
  ospkg::pkg_matches_selectors "curl [pm=apk] [pm=apt]"
}

# ---------------------------------------------------------------------------
# ospkg::parse_manifest  (direct calls — checks _M_* output variables)
# ---------------------------------------------------------------------------

@test "ospkg::parse_manifest populates _M_PKG for simple pkg list" {
  _seed_apt_context
  local _manifest
  _manifest="$(
    printf -- "--- pkg\ncurl\nwget\ngit\n"
  )"
  ospkg::parse_manifest "$_manifest"
  [[ "$_M_PKG" == *"curl"* ]]
  [[ "$_M_PKG" == *"wget"* ]]
  [[ "$_M_PKG" == *"git"* ]]
}

@test "ospkg::parse_manifest respects selector blocks on section header" {
  _seed_apt_context
  # pkg section with [pm=apk] selector should be inactive for apt context.
  local _manifest
  _manifest="$(
    printf -- "--- pkg\ncurl\n--- pkg [pm=apk]\napk-only-pkg\n"
  )"
  ospkg::parse_manifest "$_manifest"
  [[ "$_M_PKG" == *"curl"* ]]
  [[ "$_M_PKG" != *"apk-only-pkg"* ]]
}

@test "ospkg::parse_manifest populates _M_SCRIPT" {
  _seed_apt_context
  local _manifest
  _manifest="$(
    printf -- "--- pkg\ncurl\n--- script\necho hello\n"
  )"
  ospkg::parse_manifest "$_manifest"
  [[ "$_M_SCRIPT" == *"echo hello"* ]]
}

@test "ospkg::parse_manifest skips comment lines" {
  _seed_apt_context
  local _manifest
  _manifest="$(
    printf -- "--- pkg\n# a comment\ncurl\n"
  )"
  ospkg::parse_manifest "$_manifest"
  [[ "$_M_PKG" != *"# a comment"* ]]
  [[ "$_M_PKG" == *"curl"* ]]
}

@test "ospkg::parse_manifest populates _M_GROUP" {
  _seed_apt_context
  local _manifest
  _manifest="$(
    printf -- "--- group\ndevelopment-tools\n"
  )"
  ospkg::parse_manifest "$_manifest"
  [[ "$_M_GROUP" == *"development-tools"* ]]
}

@test "ospkg::parse_manifest populates _M_MODULE" {
  _seed_apt_context
  local _manifest
  _manifest="$(
    printf -- "--- module\nnodejs:18\n"
  )"
  ospkg::parse_manifest "$_manifest"
  [[ "$_M_MODULE" == *"nodejs:18"* ]]
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
  prepend_fake_bin_path
  ospkg::detect
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
