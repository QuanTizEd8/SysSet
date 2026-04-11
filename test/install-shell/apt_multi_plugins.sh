#!/bin/bash
# Verifies that multiple comma-separated plugin slugs are all cloned into the
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

# Plugins symlinked into per-user custom dir; check the remoteUser (vscode)'s home
_CUR_HOME="$(eval echo "~$(id -un)")"
_CUR_CUSTOM="${_CUR_HOME}/.config/zsh/custom"
check "per-user zsh-autosuggestions symlink exists" test -L "${_CUR_CUSTOM}/plugins/zsh-autosuggestions"
check "per-user zsh-syntax-highlighting symlink exists" test -L "${_CUR_CUSTOM}/plugins/zsh-syntax-highlighting"

reportResults
