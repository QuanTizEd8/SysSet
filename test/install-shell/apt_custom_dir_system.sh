#!/bin/bash
# Verifies that an explicit system-path ohmyzsh_custom_dir causes themes and
# plugins to be cloned there (not into <install_dir>/custom), ZSH_CUSTOM in
# the user's .zshrc points to that path, and no per-user symlinks are created.
set -e

source dev-container-features-test-lib

_HOME=/root
_ZDOTDIR="${_HOME}/.config/zsh"
_SYS_CUSTOM="/opt/zsh-custom"   # matches scenarios.json
_OMZ=/usr/local/share/oh-my-zsh

# Explicit custom dir was scaffolded with themes/plugins subdirs
check "explicit system custom dir exists" test -d "$_SYS_CUSTOM"
check "explicit system custom themes dir" test -d "${_SYS_CUSTOM}/themes"
check "explicit system custom plugins dir" test -d "${_SYS_CUSTOM}/plugins"

# Default plugin cloned into the explicit custom dir, not install_dir/custom
check "default plugin cloned at explicit path" test -d "${_SYS_CUSTOM}/plugins/zsh-syntax-highlighting/.git"
check "default plugin NOT cloned at install_dir/custom" bash -c '! test -d "${_OMZ}/custom/plugins/zsh-syntax-highlighting"'

# ZSH_CUSTOM in user rc points to the explicit system path
check "ZSH_CUSTOM set to explicit system path" grep -qF "ZSH_CUSTOM=\"${_SYS_CUSTOM}\"" "${_ZDOTDIR}/zshtheme"

# No per-user symlinks (path is not under HOME)
check "no per-user custom dir under ZDOTDIR" bash -c '! test -d "${_ZDOTDIR}/custom"'

reportResults
