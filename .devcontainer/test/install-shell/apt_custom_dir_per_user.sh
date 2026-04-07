#!/bin/bash
# Verifies that an explicit ~-prefixed ohmyzsh_custom_dir is expanded per-user
# and that installer-managed plugins are symlinked (not copied) from the system
# install into the per-user dir.
set -e

source dev-container-features-test-lib

_HOME=/root
_ZDOTDIR="${_HOME}/.config/zsh"
_USER_CUSTOM="${_HOME}/.zsh-custom"   # matches zdotdir: "~/.zsh-custom" in scenarios.json
_OMZ=/usr/local/share/oh-my-zsh
_SYS_CUSTOM="${_OMZ}/custom"

# Per-user custom dir created under HOME
check "per-user custom dir exists" test -d "$_USER_CUSTOM"
check "per-user custom themes dir exists" test -d "${_USER_CUSTOM}/themes"
check "per-user custom plugins dir exists" test -d "${_USER_CUSTOM}/plugins"

# ZSH_CUSTOM in .zshrc points to expanded per-user path
check "ZSH_CUSTOM set to per-user path" grep -qF "ZSH_CUSTOM=\"${_USER_CUSTOM}\"" "${_ZDOTDIR}/.zshrc"

# Default plugin symlinked (zsh-syntax-highlighting is the default plugin)
check "plugin symlink created in per-user dir" test -L "${_USER_CUSTOM}/plugins/zsh-syntax-highlighting"
check "plugin symlink points to system custom" bash -c 'readlink "${_USER_CUSTOM}/plugins/zsh-syntax-highlighting" | grep -qF "${_SYS_CUSTOM}/plugins/zsh-syntax-highlighting"'
check "system plugin dir still exists at target" test -d "${_SYS_CUSTOM}/plugins/zsh-syntax-highlighting/.git"

# System custom dir still has the real clone
check "plugin NOT directly cloned in per-user dir" bash -c '! test -d "${_USER_CUSTOM}/plugins/zsh-syntax-highlighting/.git"'

reportResults
