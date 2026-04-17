#!/bin/bash
# Verifies that custom install directories are respected for both Oh My Zsh
# and Oh My Bash, and that the default paths are NOT populated.
set -e

source dev-container-features-test-lib

_OMZ=/opt/oh-my-zsh
_OMB=/opt/oh-my-bash
_HOME=/root
_ZDOTDIR="${_HOME}/.config/zsh"
_OMZ_CUSTOM="${_ZDOTDIR}/custom"

# Custom paths exist
check "oh-my-zsh at custom path" test -d "$_OMZ"
check "oh-my-zsh main script at custom path" test -f "${_OMZ}/oh-my-zsh.sh"
check "oh-my-bash at custom path" test -d "$_OMB"
check "oh-my-bash main script at custom path" test -f "${_OMB}/oh-my-bash.sh"

# Default paths NOT populated
check "omz not at default path" bash -c '! test -d /usr/local/share/oh-my-zsh'
check "omb not at default path" bash -c '! test -d /usr/local/share/oh-my-bash'

# System custom scaffold under custom OMZ install dir
_SYS_CUSTOM="${_OMZ}/custom"
check "oh-my-zsh.remote git config set at custom path" bash -c 'test "$(git -C "'"$_OMZ"'" config oh-my-zsh.remote)" = "origin"'
check "system custom themes dir at custom OMZ path" test -d "${_SYS_CUSTOM}/themes"
check "system custom plugins dir at custom OMZ path" test -d "${_SYS_CUSTOM}/plugins"
check "default plugin cloned at custom OMZ path" test -d "${_SYS_CUSTOM}/plugins/zsh-syntax-highlighting/.git"

# Root user configured (via add_container_user, _CONTAINER_USER=root)
check "root .zshenv exists" test -f "${_HOME}/.zshenv"
check "root ZDOTDIR/.zshrc exists" test -f "${_ZDOTDIR}/.zshrc"
check "root .bashrc exists" test -f "${_HOME}/.bashrc"
check ".zshenv sets ZDOTDIR" grep -qF "ZDOTDIR=\"${_ZDOTDIR}\"" "${_HOME}/.zshenv"
_ZSHTHEME="${_ZDOTDIR}/zshtheme"
check "zshtheme file written" test -f "$_ZSHTHEME"
check ".zshrc sets ZSH to custom path" grep -qF "export ZSH=\"${_OMZ}\"" "$_ZSHTHEME"

# Per-user custom dir uses ZDOTDIR/custom (not install_dir/custom)
check "per-user OMZ custom dir exists" test -d "${_OMZ_CUSTOM}"
check "ZSH_CUSTOM points to custom ZDOTDIR/custom" grep -qF "ZSH_CUSTOM=\"${_OMZ_CUSTOM}\"" "$_ZSHTHEME"

reportResults
