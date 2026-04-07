#!/bin/bash
# Verifies that an explicit zdotdir option is honoured: zsh config files land
# in the specified directory rather than the default ~/.config/zsh.
set -e

source dev-container-features-test-lib

_HOME=/root
_ZDOTDIR="${_HOME}/.zsh"   # matches zdotdir: "~/.zsh" in scenarios.json

# .zshenv in HOME, not ZDOTDIR
check ".zshenv exists in HOME" test -f "${_HOME}/.zshenv"
check ".zshrc NOT in HOME" bash -c '! test -f "${_HOME}/.zshrc"'

# ZDOTDIR injection uses the custom value
check ".zshenv sets ZDOTDIR to custom path" grep -qF "ZDOTDIR=\"${_ZDOTDIR}\"" "${_HOME}/.zshenv"

# Zsh config files in custom ZDOTDIR
check "custom ZDOTDIR exists" test -d "$_ZDOTDIR"
check "custom ZDOTDIR/.zshrc exists" test -f "${_ZDOTDIR}/.zshrc"
check "custom ZDOTDIR/.zprofile exists" test -f "${_ZDOTDIR}/.zprofile"

# Default ~/.config/zsh NOT created for zshrc
check "default .config/zsh/.zshrc NOT present" bash -c '! test -f "${_HOME}/.config/zsh/.zshrc"'

# OMZ custom dir defaults to ZDOTDIR/custom (the custom ZDOTDIR)
check "OMZ custom dir under custom ZDOTDIR" test -d "${_ZDOTDIR}/custom"
check "ZSH_CUSTOM points to custom ZDOTDIR/custom" grep -qF "ZSH_CUSTOM=\"${_ZDOTDIR}/custom\"" "${_ZDOTDIR}/.zshrc"

reportResults
