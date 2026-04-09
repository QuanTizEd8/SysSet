#!/bin/bash
# Verifies that add_user_config with an explicit username configures that user.
set -e

source dev-container-features-test-lib

_HOME=/home/devuser
_ZDOTDIR="${_HOME}/.config/zsh"

check "devuser .zshenv exists" test -f "${_HOME}/.zshenv"
check "devuser ZDOTDIR/.zshrc exists" test -f "${_ZDOTDIR}/.zshrc"
check "devuser .bashrc exists" test -f "${_HOME}/.bashrc"
check "devuser zshtheme file written" test -f "${_ZDOTDIR}/zshtheme"
check ".zshenv sets ZDOTDIR" grep -qF "ZDOTDIR=\"${_ZDOTDIR}\"" "${_HOME}/.zshenv"
check "devuser HOME owned by devuser" bash -c '[ "$(stat -c %U /home/devuser)" = "devuser" ]'

# Root should NOT be configured (add_container_user_config and add_remote_user_config are false)
check "root ZDOTDIR/.zshrc NOT configured" bash -c '! test -f /root/.config/zsh/.zshrc'

reportResults
