#!/bin/bash
# Verifies that setting ohmyzsh_theme=romkatv/powerlevel10k installs the p10k
# theme and configures root's ZDOTDIR/.zshrc with the p10k guarded block and
# correct ZSH_CUSTOM. Font installation is tested separately in install-fonts.
set -e

source dev-container-features-test-lib

_OMZ=/usr/local/share/oh-my-zsh
_CUSTOM="${_OMZ}/custom"
_HOME=/root
_ZDOTDIR="${_HOME}/.config/zsh"
_USER_CUSTOM="${_ZDOTDIR}/custom"

# Theme installation in system custom dir
check "powerlevel10k theme cloned" test -d "${_CUSTOM}/themes/powerlevel10k/.git"
check "powerlevel10k.zsh-theme file present" test -f "${_CUSTOM}/themes/powerlevel10k/powerlevel10k.zsh-theme"

# Root user zshtheme written to ZDOTDIR
_ZSHTHEME="${_ZDOTDIR}/zshtheme"
check "ZDOTDIR/.zshrc exists" test -f "${_ZDOTDIR}/.zshrc"
check "zshtheme file written" test -f "$_ZSHTHEME"
check "zshtheme sets ZSH_THEME to p10k" grep -q 'ZSH_THEME=.*powerlevel10k' "$_ZSHTHEME"
check "zshtheme disables p10k wizard" grep -qF 'POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true' "$_ZSHTHEME"
check "zshtheme: wizard flag appears before source oh-my-zsh.sh" bash -c 'awk "/POWERLEVEL9K_DISABLE/{w=NR} /source.*oh-my-zsh/{s=NR} END{exit !(w>0 && s>0 && w<s)}" "'"$_ZSHTHEME"'"'
check "zshtheme sources oh-my-zsh.sh" grep -q 'oh-my-zsh.sh' "$_ZSHTHEME"
check "zshtheme sources .p10k.zsh" grep -q 'p10k.zsh' "$_ZSHTHEME"

# ZSH_CUSTOM points to per-user dir
check "zshtheme sets ZSH_CUSTOM to per-user path" grep -qF "ZSH_CUSTOM=\"${_USER_CUSTOM}\"" "$_ZSHTHEME"

# Per-user custom dir has symlink to system p10k theme
check "p10k symlink in user custom themes" test -L "${_USER_CUSTOM}/themes/powerlevel10k"
check "p10k symlink target is system custom" bash -c "readlink '${_USER_CUSTOM}/themes/powerlevel10k' | grep -qF \"${_CUSTOM}/themes/powerlevel10k\""

# p10k config deployed
check "root .p10k.zsh exists" test -f "${_HOME}/.p10k.zsh"

reportResults
