#!/usr/bin/env bats
# Unit tests for install-homebrew's direct package-manager update path.

bats_require_minimum_version 1.5.0

setup() {
  export INSTALL_TEST_FIXTURE=install-homebrew
  load 'helpers/ensure_framework'
  install_test__ensure_framework
  _run_log="${BATS_TEST_TMPDIR}/ospkg-run.log"
}

@test "install-homebrew routes its optional brew update through the package-manager retry runner" {
  UPDATE=true
  _RESOLVED_PREFIX="${BATS_TEST_TMPDIR}/homebrew"
  enforce_options() { :; }
  _ospkg__run_network() { printf '%s\n' "$*" > "$_run_log"; }
  logging__info() { :; }
  logging__success() { :; }
  logging__warn() { :; }

  run __install_finish_post
  assert_success
  assert [ "$(cat "$_run_log")" = "--operation update _brew_run_as_install_user ${_RESOLVED_PREFIX}/bin/brew update" ]
}
