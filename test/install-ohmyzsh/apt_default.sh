#!/bin/bash
# Verifies the default installation: oh-my-zsh core, powerlevel10k theme,
# zsh-syntax-highlighting plugin, MesloLGS Nerd Fonts, and git config metadata.
set -e

source dev-container-features-test-lib

_OMZ=/usr/local/share/oh-my-zsh
_CUSTOM="${_OMZ}/custom"
_FONTS=/usr/share/fonts/MesloLGS

# Core install
check "zsh is installed" command -v zsh
check "oh-my-zsh install dir exists" test -d "$_OMZ"
check "oh-my-zsh main script exists" test -f "${_OMZ}/oh-my-zsh.sh"

# omz update metadata
check "oh-my-zsh.remote git config set to origin" bash -c '[ "$(git -C "$_OMZ" config oh-my-zsh.remote)" = "origin" ]'
check "oh-my-zsh.branch git config set to master" bash -c '[ "$(git -C "$_OMZ" config oh-my-zsh.branch)" = "master" ]'

# ZSH_CUSTOM scaffold
check "ZSH_CUSTOM themes dir exists" test -d "${_CUSTOM}/themes"
check "ZSH_CUSTOM plugins dir exists" test -d "${_CUSTOM}/plugins"

# Default theme and plugin
check "powerlevel10k theme cloned" test -d "${_CUSTOM}/themes/powerlevel10k/.git"
check "powerlevel10k.zsh-theme file present" test -f "${_CUSTOM}/themes/powerlevel10k/powerlevel10k.zsh-theme"
check "zsh-syntax-highlighting plugin cloned" test -d "${_CUSTOM}/plugins/zsh-syntax-highlighting/.git"

# All four MesloLGS fonts
check "MesloLGS Regular font present" test -f "${_FONTS}/MesloLGS NF Regular.ttf"
check "MesloLGS Bold font present" test -f "${_FONTS}/MesloLGS NF Bold.ttf"
check "MesloLGS Italic font present" test -f "${_FONTS}/MesloLGS NF Italic.ttf"
check "MesloLGS Bold Italic font present" test -f "${_FONTS}/MesloLGS NF Bold Italic.ttf"

reportResults
