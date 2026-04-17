#!/bin/bash
# Verifies that add_remote_user=true configures the user identified by
# the remoteUser field (injected as _REMOTE_USER by the devcontainer CLI).
set -e

source dev-container-features-test-lib

_HOME=/home/vscode
_ZDOTDIR="${_HOME}/.config/zsh"

check "vscode .zshenv exists" test -f "${_HOME}/.zshenv"
check "vscode ZDOTDIR/.zshrc exists" test -f "${_ZDOTDIR}/.zshrc"
check "vscode .bashrc exists" test -f "${_HOME}/.bashrc"
check "vscode zshtheme file written" test -f "${_ZDOTDIR}/zshtheme"
check ".zshenv sets ZDOTDIR" grep -qF "ZDOTDIR=\"${_ZDOTDIR}\"" "${_HOME}/.zshenv"
check "vscode HOME owned by vscode" bash -c '[ "$(stat -c %U /home/vscode)" = "vscode" ]'

# Root should NOT be configured (containerUser resolves to vscode, not root)
check "root ZDOTDIR/.zshrc NOT configured" bash -c '! test -f /root/.config/zsh/.zshrc'

reportResults
