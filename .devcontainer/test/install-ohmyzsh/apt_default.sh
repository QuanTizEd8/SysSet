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
check "oh-my-zsh.remote git config set to origin" bash -c 'test "$(git -C /usr/local/share/oh-my-zsh config oh-my-zsh.remote)" = "origin"'
check "oh-my-zsh.branch git config set to master" bash -c 'test "$(git -C /usr/local/share/oh-my-zsh config oh-my-zsh.branch)" = "master"'

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

# Global zshrc (configure_zshrc defaults to true)
_ZSHRC=/etc/zsh/zshrc
check "global zshrc exists" test -f "$_ZSHRC"
check "global zshrc has BEGIN marker" grep -qF '# BEGIN install-ohmyzsh' "$_ZSHRC"
check "global zshrc exports ZSH" grep -q 'export ZSH=' "$_ZSHRC"
check "global zshrc exports ZSH_CUSTOM" grep -q 'export ZSH_CUSTOM=' "$_ZSHRC"
check "global zshrc sets ZSH_THEME dir/file format" grep -qE 'ZSH_THEME="[^/]+/[^/]+"' "$_ZSHRC"
check "global zshrc disables omz update" grep -qF "zstyle ':omz:update' mode disabled" "$_ZSHRC"
check "global zshrc disables p10k wizard" grep -qF 'POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true' "$_ZSHRC"
check "global zshrc: wizard flag before source" bash -c 'awk "/POWERLEVEL9K_DISABLE/{w=NR} /source.*oh-my-zsh/{s=NR} END{exit !(w>0 && s>0 && w<s)}" /etc/zsh/zshrc'
check "global zshrc sources oh-my-zsh.sh" grep -q 'oh-my-zsh.sh' "$_ZSHRC"
check "global zshrc sources .p10k.zsh if present" grep -qF '.p10k.zsh' "$_ZSHRC"

reportResults
