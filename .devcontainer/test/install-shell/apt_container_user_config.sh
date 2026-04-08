#!/bin/bash
# Verifies that add_container_user_config=true configures the user identified by
# the containerUser field (injected as _CONTAINER_USER by the devcontainer CLI).
set -e

source dev-container-features-test-lib

_HOME=/home/vscode
_ZDOTDIR="${_HOME}/.config/zsh"

check "vscode .zshenv exists" test -f "${_HOME}/.zshenv"
check "vscode ZDOTDIR/.zshrc exists" test -f "${_ZDOTDIR}/.zshrc"
check "vscode .bashrc exists" test -f "${_HOME}/.bashrc"
check "vscode .zshrc has OMZ block" grep -qF '# BEGIN install-shell-ohmyzsh' "${_ZDOTDIR}/.zshrc"
check ".zshenv sets ZDOTDIR" grep -qF "ZDOTDIR=\"${_ZDOTDIR}\"" "${_HOME}/.zshenv"
check "vscode HOME owned by vscode" bash -c '[ "$(stat -c %U /home/vscode)" = "vscode" ]'

# Root should NOT be configured (add_root_user_config defaults to false)
check "root ZDOTDIR/.zshrc NOT configured" bash -c '! test -f /root/.config/zsh/.zshrc'

reportResults
