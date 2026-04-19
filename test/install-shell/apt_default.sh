#!/bin/bash
# Verifies the default installation: zsh, Oh My Zsh with default plugin,
# Oh My Bash, Starship, system config files, and BASH_ENV.
set -e

source dev-container-features-test-lib

_OMZ=/usr/local/share/oh-my-zsh
_OMB=/usr/local/share/oh-my-bash

# --- Shells ---
check "zsh is installed" command -v zsh
check "bash is installed" command -v bash
check "git is installed" command -v git

# --- Oh My Zsh ---
check "oh-my-zsh install dir exists" test -d "$_OMZ"
check "oh-my-zsh main script exists" test -f "${_OMZ}/oh-my-zsh.sh"
check "oh-my-zsh.remote git config set" bash -c 'test "$(git -C '"$_OMZ"' config oh-my-zsh.remote)" = "origin"'
check "oh-my-zsh.branch git config set" bash -c 'test "$(git -C '"$_OMZ"' config oh-my-zsh.branch)" = "master"'
check "ZSH_CUSTOM themes dir scaffolded" test -d "${_OMZ}/custom/themes"
check "ZSH_CUSTOM plugins dir scaffolded" test -d "${_OMZ}/custom/plugins"
check "zsh-syntax-highlighting plugin cloned" test -d "${_OMZ}/custom/plugins/zsh-syntax-highlighting/.git"

# --- Oh My Bash ---
check "oh-my-bash install dir exists" test -d "$_OMB"
check "oh-my-bash main script exists" test -f "${_OMB}/oh-my-bash.sh"

# --- Starship ---
check "starship binary installed" command -v starship

# --- System config files ---
check "/etc/profile exists" test -f /etc/profile
check "/etc/bash.bashrc or equivalent exists" bash -c 'test -f /etc/bash.bashrc || test -f /etc/bashrc || test -f /etc/bash/bashrc'
check "/etc/shellenv exists" test -f /etc/shellenv
check "/etc/shellrc exists" test -f /etc/shellrc

# --- BASH_ENV set in /etc/environment ---
check "BASH_ENV set in /etc/environment" grep -q '^BASH_ENV=' /etc/environment

# --- Zsh system-wide config files ---
check "zsh system zshenv exists" bash -c 'test -f /etc/zsh/zshenv || test -f /etc/zshenv'
check "zsh system zshrc exists" bash -c 'test -f /etc/zsh/zshrc || test -f /etc/zshrc'
check "zsh system zprofile exists" bash -c 'test -f /etc/zsh/zprofile || test -f /etc/zprofile'
check "zsh zprofile sources /etc/profile" bash -c 'grep -q "/etc/profile" /etc/zsh/zprofile 2>/dev/null || grep -q "/etc/profile" /etc/zprofile 2>/dev/null'

reportResults
