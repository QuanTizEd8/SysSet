#!/bin/bash
# Verifies that multiple plugin slugs (scenario: newline-delimited array) are cloned into the
# system ZSH_CUSTOM dir, and symlinked into the per-user custom dir.
set -e

source dev-container-features-test-lib

_OMZ=/usr/local/share/oh-my-zsh
_SYS_CUSTOM="${_OMZ}/custom"
_HOME=/root
_USER_CUSTOM="${_HOME}/.config/zsh/custom"

# Plugins cloned into system custom dir
check "zsh-autosuggestions cloned in system custom" test -d "${_SYS_CUSTOM}/plugins/zsh-autosuggestions/.git"
check "zsh-syntax-highlighting cloned in system custom" test -d "${_SYS_CUSTOM}/plugins/zsh-syntax-highlighting/.git"

# Plugins symlinked into per-user custom dir; this scenario uses remoteUser=vscode.
_CUR_CUSTOM="/home/vscode/.config/zsh/custom"
check "per-user zsh-autosuggestions symlink exists" test -L "${_CUR_CUSTOM}/plugins/zsh-autosuggestions"
check "per-user zsh-syntax-highlighting symlink exists" test -L "${_CUR_CUSTOM}/plugins/zsh-syntax-highlighting"

reportResults
