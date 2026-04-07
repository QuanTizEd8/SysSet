#!/bin/bash
# Verifies the default installation: zsh, Oh My Zsh with default plugin,
# Oh My Bash, Starship, Nerd Fonts, and system config files deployed.
set -e

source dev-container-features-test-lib

_OMZ=/usr/local/share/oh-my-zsh
_OMB=/usr/local/share/oh-my-bash
_FONTS=/usr/share/fonts

# --- Shells ---
check "zsh is installed" command -v zsh
check "bash is installed" command -v bash

# --- Oh My Zsh ---
check "oh-my-zsh install dir exists" test -d "$_OMZ"
check "oh-my-zsh main script exists" test -f "${_OMZ}/oh-my-zsh.sh"
check "oh-my-zsh.remote git config set" bash -c 'test "$(git -C '"$_OMZ"' config oh-my-zsh.remote)" = "origin"'
check "oh-my-zsh.branch git config set" bash -c 'test "$(git -C '"$_OMZ"' config oh-my-zsh.branch)" = "master"'
check "ZSH_CUSTOM dirs scaffolded" test -d "${_OMZ}/custom/themes" -a -d "${_OMZ}/custom/plugins"
check "zsh-syntax-highlighting plugin cloned" test -d "${_OMZ}/custom/plugins/zsh-syntax-highlighting/.git"

# --- Oh My Bash ---
check "oh-my-bash install dir exists" test -d "$_OMB"
check "oh-my-bash main script exists" test -f "${_OMB}/oh-my-bash.sh"

# --- Starship ---
check "starship binary installed" command -v starship

# --- Fonts ---
check "font directory exists" test -d "$_FONTS"
check "at least one nerd font installed" bash -c 'find "$_FONTS" -name "*.ttf" -o -name "*.otf" | head -1 | grep -q .'

# --- System config files ---
check "/etc/profile exists" test -f /etc/profile
check "/etc/bash.bashrc or equivalent exists" bash -c 'test -f /etc/bash.bashrc || test -f /etc/bashrc || test -f /etc/bash/bashrc'

reportResults
