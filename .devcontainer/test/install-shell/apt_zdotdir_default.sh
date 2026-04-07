#!/bin/bash
# Verifies the default ZDOTDIR behaviour: zsh config files land in
# ~/.config/zsh, .zshenv in HOME sets ZDOTDIR, and the OMZ block is
# injected into $ZDOTDIR/.zshrc (not $HOME/.zshrc).
set -e

source dev-container-features-test-lib

_HOME=/root
_ZDOTDIR="${_HOME}/.config/zsh"

# .zshenv in HOME injects ZDOTDIR
check ".zshenv exists in HOME" test -f "${_HOME}/.zshenv"
check ".zshrc NOT in HOME" bash -c '! test -f "${_HOME}/.zshrc"'
check ".zprofile NOT in HOME" bash -c '! test -f "${_HOME}/.zprofile"'
check ".zlogin NOT in HOME" bash -c '! test -f "${_HOME}/.zlogin"'

# ZDOTDIR injection block present in .zshenv
check ".zshenv has ZDOTDIR block" grep -qF '# BEGIN install-shell-zdotdir' "${_HOME}/.zshenv"
check ".zshenv ZDOTDIR value is .config/zsh" grep -qF "ZDOTDIR=\"${_ZDOTDIR}\"" "${_HOME}/.zshenv"

# Zsh config files in ZDOTDIR
check "ZDOTDIR exists" test -d "$_ZDOTDIR"
check "ZDOTDIR/.zshrc exists" test -f "${_ZDOTDIR}/.zshrc"
check "ZDOTDIR/.zprofile exists" test -f "${_ZDOTDIR}/.zprofile"
check "ZDOTDIR/.zlogin exists" test -f "${_ZDOTDIR}/.zlogin"

# OMZ block written to ZDOTDIR/.zshrc
check "ZDOTDIR/.zshrc has OMZ block" grep -qF '# BEGIN install-shell-ohmyzsh' "${_ZDOTDIR}/.zshrc"
check "ZDOTDIR/.zshrc sets ZSH_CUSTOM to per-user path" grep -qF "ZSH_CUSTOM=\"${_ZDOTDIR}/custom\"" "${_ZDOTDIR}/.zshrc"

# Per-user custom dir is under ZDOTDIR
check "ZDOTDIR/custom exists" test -d "${_ZDOTDIR}/custom"
check "ZDOTDIR/custom/themes exists" test -d "${_ZDOTDIR}/custom/themes"
check "ZDOTDIR/custom/plugins exists" test -d "${_ZDOTDIR}/custom/plugins"

# Ownership: entire HOME owned by root
check "HOME owned by user" bash -c '[ "$(stat -c %U '"$_HOME"')" = "root" ]'
check "ZDOTDIR owned by user" bash -c '[ "$(stat -c %U '"$_ZDOTDIR"')" = "root" ]'

reportResults
