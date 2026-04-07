#!/bin/bash
# Verifies that set_user_shells=zsh changes the default login shell and that
# zsh is registered in /etc/shells.
set -e

source dev-container-features-test-lib

_ZSH_PATH="$(command -v zsh)"

check "zsh is installed" test -n "$_ZSH_PATH"
check "zsh listed in /etc/shells" grep -qx "$_ZSH_PATH" /etc/shells
check "root default shell is zsh" bash -c '[ "$(getent passwd root | cut -d: -f7)" = "'"$_ZSH_PATH"'" ]'

reportResults
