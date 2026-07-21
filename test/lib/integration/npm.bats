#!/usr/bin/env bats
# Integration tests for lib/npm.bash — npm__install_bundled against real network.
#
# These tests run whenever the integration tier is selected and require a real
# internet connection. They perform actual Node.js and npm package downloads
# (via the bundled npm shipped with Node.js) to verify correct end-to-end
# behavior of npm__install_bundled and related functions. Alpine alone is
# skipped because the pre-built Node.js binaries are linked against glibc.
#
# Two fixture packages are used:
#
#   semver@7.6.3  — pure JS, no lifecycle scripts, no optional deps.
#                   Tests the core install/idempotency/update/uninstall flow.
#
#   esbuild       — has a postinstall script that calls bare 'node install.js'
#                   to fetch a platform-specific native binary.  Exercises the
#                   lifecycle-script code path and verifies that the bundled
#                   Node.js bin directory is prepended to PATH for npm scripts.
#
# Note: optional platform-dep resolution (the primary motivation for the
# bundled-npm approach) is exercised by the install-codex feature tests.

bats_require_minimum_version 1.5.0

# Tests share one file-scoped installation prefix and install log.
export BATS_NO_PARALLELIZE_WITHIN_FILE=true

_NPM_INT_PKG="semver"
_NPM_INT_PKG_VER="7.6.3"
_NPM_INT_CMD="semver"

# ---------------------------------------------------------------------------
# setup / teardown
# ---------------------------------------------------------------------------

setup() {
  load '../helpers/common'
  load '../helpers/test_tools'
  reload_lib
  test_tools__wire_jq
  lib_test__npm_network_bounded

  if [[ "$(os__platform 2> /dev/null)" == "alpine" ]]; then
    skip "pre-built Node.js from nodejs.org is not supported on Alpine (musl libc)"
  fi

  # Shared prefix reused by the common layout/runtime assertions. Its first
  # setup downloads the fixture; later setups reuse it. Update, uninstall, and
  # esbuild tests use separate prefixes and perform their own downloads.
  _INT_PREFIX="${BATS_FILE_TMPDIR}/semver-bundled"

  if ! npm__is_bundled "${_INT_PREFIX}/bin/${_NPM_INT_CMD}" 2> /dev/null; then
    npm__install_bundled \
      --package "$_NPM_INT_PKG" \
      --version "$_NPM_INT_PKG_VER" \
      --cmd "$_NPM_INT_CMD" \
      --prefix "$_INT_PREFIX" \
      > "${BATS_FILE_TMPDIR}/install.log" 2>&1 ||
      fail "npm__install_bundled failed; see ${BATS_FILE_TMPDIR}/install.log"
  fi
}

# ---------------------------------------------------------------------------
# Node.js runtime
# ---------------------------------------------------------------------------

@test "npm__install_bundled (real): Node.js binary is present and executable" {
  [ -x "${_INT_PREFIX}/node/current/bin/node" ]
  run "${_INT_PREFIX}/node/current/bin/node" --version
  assert_success
  assert_output --regexp "^v[0-9]+\.[0-9]+\.[0-9]+$"
}

# ---------------------------------------------------------------------------
# Package layout
# ---------------------------------------------------------------------------

@test "npm__install_bundled (real): node_modules/ directory is created" {
  [ -d "${_INT_PREFIX}/pkg/current/node_modules" ]
}

@test "npm__install_bundled (real): .bin/<cmd> entry is a valid symlink" {
  local _bin_entry="${_INT_PREFIX}/pkg/current/node_modules/.bin/${_NPM_INT_CMD}"
  [ -L "$_bin_entry" ] # is a symlink
  [ -e "$_bin_entry" ] # symlink is not broken
}

@test "npm__install_bundled (real): node/current points to a real Node.js version dir" {
  local _target
  _target="$(readlink "${_INT_PREFIX}/node/current")"
  [[ "$_target" == v* ]]
  [ -d "${_INT_PREFIX}/node/${_target}" ]
}

@test "npm__install_bundled (real): pkg/current points to the installed package version" {
  local _target
  _target="$(readlink "${_INT_PREFIX}/pkg/current")"
  assert_equal "$_target" "$_NPM_INT_PKG_VER"
}

# ---------------------------------------------------------------------------
# Metadata
# ---------------------------------------------------------------------------

@test "npm__install_bundled (real): installed-version metadata matches pinned version" {
  local _ver
  _ver="$(cat "${_INT_PREFIX}/.metadata/installed-version")"
  assert_equal "$_ver" "$_NPM_INT_PKG_VER"
}

@test "npm__install_bundled (real): node-version metadata is a valid version string" {
  local _node_ver
  _node_ver="$(cat "${_INT_PREFIX}/.metadata/node-version")"
  [[ "$_node_ver" == v[0-9]* ]]
}

# ---------------------------------------------------------------------------
# Wrapper
# ---------------------------------------------------------------------------

@test "npm__install_bundled (real): wrapper script is executable" {
  [ -x "${_INT_PREFIX}/bin/${_NPM_INT_CMD}" ]
}

@test "npm__install_bundled (real): wrapper executes the package CLI successfully" {
  # 'semver 1.2.3' validates the string and prints it if it is valid semver.
  run "${_INT_PREFIX}/bin/${_NPM_INT_CMD}" "1.2.3"
  assert_success
  assert_output "1.2.3"
}

@test "npm__install_bundled (real): wrapper passes all user arguments through" {
  # 'semver -r ">=1.0.0" 1.2.3' prints the version when it satisfies the range.
  run "${_INT_PREFIX}/bin/${_NPM_INT_CMD}" -r ">=1.0.0" "1.2.3"
  assert_success
  assert_output --partial "1.2.3"
}

@test "npm__install_bundled (real): wrapper forwards exit code from the CLI" {
  # 'semver invalid' exits non-zero for an invalid semver string.
  run "${_INT_PREFIX}/bin/${_NPM_INT_CMD}" "not-a-version"
  assert_failure
}

# ---------------------------------------------------------------------------
# npm__is_bundled
# ---------------------------------------------------------------------------

@test "npm__is_bundled (real): returns true for the installed wrapper" {
  run npm__is_bundled "${_INT_PREFIX}/bin/${_NPM_INT_CMD}"
  assert_success
}

@test "npm__is_bundled (real): returns false for an arbitrary binary" {
  run npm__is_bundled "$(command -v bash)"
  assert_failure
}

# ---------------------------------------------------------------------------
# Idempotency
# ---------------------------------------------------------------------------

@test "npm__install_bundled (real): second call skips Node.js and package downloads" {
  run npm__install_bundled \
    --package "$_NPM_INT_PKG" \
    --version "$_NPM_INT_PKG_VER" \
    --cmd "$_NPM_INT_CMD" \
    --prefix "$_INT_PREFIX"
  assert_success
  assert_output --partial "already present; skipping download"
  assert_output --partial "already installed; skipping"
}

# ---------------------------------------------------------------------------
# Update
# ---------------------------------------------------------------------------

@test "npm__install_bundled (real) --update: installs new version and prunes old" {
  local _upd_prefix="${BATS_TEST_TMPDIR}/semver-update"

  # Start from an older pinned version.
  npm__install_bundled \
    --package "$_NPM_INT_PKG" \
    --version "7.6.0" \
    --cmd "$_NPM_INT_CMD" \
    --prefix "$_upd_prefix" \
    > "${BATS_TEST_TMPDIR}/install-old.log" 2>&1 ||
    skip "initial install for update test failed"

  assert_equal "$(cat "${_upd_prefix}/.metadata/installed-version")" "7.6.0"

  # Update to the pinned version.
  run npm__install_bundled \
    --package "$_NPM_INT_PKG" \
    --version "$_NPM_INT_PKG_VER" \
    --cmd "$_NPM_INT_CMD" \
    --prefix "$_upd_prefix" \
    --update
  assert_success

  # Metadata reflects the new version.
  assert_equal "$(cat "${_upd_prefix}/.metadata/installed-version")" "$_NPM_INT_PKG_VER"

  # Wrapper produces the new version's output.
  run "${_upd_prefix}/bin/${_NPM_INT_CMD}" "2.0.0"
  assert_success
  assert_output "2.0.0"

  # Old version directory is pruned.
  [ ! -d "${_upd_prefix}/pkg/7.6.0" ]
}

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------

@test "npm__uninstall_bundled (real): removes the entire prefix" {
  local _uninst_prefix="${BATS_TEST_TMPDIR}/semver-uninst"

  npm__install_bundled \
    --package "$_NPM_INT_PKG" \
    --version "$_NPM_INT_PKG_VER" \
    --cmd "$_NPM_INT_CMD" \
    --prefix "$_uninst_prefix" \
    > "${BATS_TEST_TMPDIR}/install-uninst.log" 2>&1 ||
    skip "install for uninstall test failed"

  run npm__uninstall_bundled --prefix "$_uninst_prefix"
  assert_success
  [ ! -d "$_uninst_prefix" ]
}

@test "npm__uninstall_bundled (real): --bin mode derives prefix and removes it" {
  local _uninst_prefix="${BATS_TEST_TMPDIR}/semver-uninst-bin"

  npm__install_bundled \
    --package "$_NPM_INT_PKG" \
    --version "$_NPM_INT_PKG_VER" \
    --cmd "$_NPM_INT_CMD" \
    --prefix "$_uninst_prefix" \
    > "${BATS_TEST_TMPDIR}/install-uninst-bin.log" 2>&1 ||
    skip "install for uninstall-bin test failed"

  run npm__uninstall_bundled --bin "${_uninst_prefix}/bin/${_NPM_INT_CMD}"
  assert_success
  [ ! -d "$_uninst_prefix" ]
}

# ---------------------------------------------------------------------------
# Lifecycle scripts
# ---------------------------------------------------------------------------

@test "npm__install_bundled (real): installs a package whose postinstall calls bare 'node'" {
  # esbuild has a postinstall script ('node install.js') that downloads the
  # platform-specific native binary. npm 10 removed
  # --scripts-prepend-node-path, so production explicitly prepends the bundled
  # Node.js bin directory to PATH for lifecycle scripts.
  local _esbuild_prefix="${BATS_TEST_TMPDIR}/esbuild-bundled"
  run npm__install_bundled \
    --package "esbuild" \
    --version "0.21.5" \
    --cmd "esbuild" \
    --prefix "$_esbuild_prefix"
  assert_success
  # Verify the native binary was fetched and the wrapper runs it correctly.
  run "${_esbuild_prefix}/bin/esbuild" --version
  assert_success
  assert_output "0.21.5"
}
