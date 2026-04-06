#!/bin/bash
# Verifies that set_default_shell_for=root changes root's login shell to zsh
# and that zsh is registered in /etc/shells (required by chsh).
set -e

source dev-container-features-test-lib

_ZSH_PATH="$(command -v zsh)"

check "zsh is installed" test -n "$_ZSH_PATH"
check "zsh listed in /etc/shells" grep -qx "$_ZSH_PATH" /etc/shells
check "root default shell is zsh" bash -c '[ "$(getent passwd root | cut -d: -f7)" = "'"$_ZSH_PATH"'" ]'

reportResults
