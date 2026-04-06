#!/bin/bash
# Verifies that a custom install_dir places oh-my-zsh at the specified path,
# that ZSH_CUSTOM defaults to <install_dir>/custom, and that configure_zshrc
# reflects both custom paths in the exported environment variables.
set -e

source dev-container-features-test-lib

_OMZ=/opt/oh-my-zsh
_CUSTOM="${_OMZ}/custom"

check "oh-my-zsh installed at custom path" test -d "$_OMZ"
check "oh-my-zsh main script at custom path" test -f "${_OMZ}/oh-my-zsh.sh"
check "oh-my-zsh.remote git config set" bash -c 'test "$(git -C /opt/oh-my-zsh config oh-my-zsh.remote)" = "origin"'
check "theme cloned under custom install_dir" test -d "${_CUSTOM}/themes/powerlevel10k/.git"
check "plugin cloned under custom install_dir" test -d "${_CUSTOM}/plugins/zsh-syntax-highlighting/.git"
check "omz not cloned at default path" bash -c '! test -d /usr/local/share/oh-my-zsh'
check "/etc/zsh/zshrc exports ZSH to custom path" grep -qF 'export ZSH="/opt/oh-my-zsh"' /etc/zsh/zshrc
check "/etc/zsh/zshrc exports ZSH_CUSTOM derived from install_dir" grep -qF 'export ZSH_CUSTOM="/opt/oh-my-zsh/custom"' /etc/zsh/zshrc

reportResults
