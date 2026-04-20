#!/usr/bin/env bats
# Unit tests for lib/str.sh

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
  reload_lib str.sh
}

# ---------------------------------------------------------------------------
# str__basename_each
# ---------------------------------------------------------------------------

@test "str__basename_each prints basenames one per line" {
  run str__basename_each "zsh-users/zsh-autosuggestions" "zsh-users/zsh-syntax-highlighting"
  assert_output "zsh-autosuggestions
zsh-syntax-highlighting"
  assert_success
}

@test "str__basename_each prints nothing when given no arguments" {
  run bash -c 'source "$1" && str__basename_each' _ "${LIB_ROOT}/str.sh"
  assert_output ""
  assert_success
}

@test "str__basename_each skips an empty argument" {
  run str__basename_each "" "zsh-users/zsh-autosuggestions"
  assert_output "zsh-autosuggestions"
  assert_success
}
