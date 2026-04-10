#!/bin/bash
# Verifies that user_config_mode=skip does not write any per-user dotfiles
# while the system-wide install (OMZ, OMB, system config files) still succeeds.
set -e

source dev-container-features-test-lib

_HOME=/root
_ZDOTDIR="${_HOME}/.config/zsh"

# --- Frameworks still installed system-wide ---
check "oh-my-zsh installed" test -d /usr/local/share/oh-my-zsh
check "oh-my-bash installed" test -d /usr/local/share/oh-my-bash

# --- No per-user theme files written when mode=skip ---
check "root zshtheme not written" bash -c '! test -f "${_ZDOTDIR}/zshtheme"'
check "root bashtheme not written" bash -c '! test -f "/root/.config/bash/bashtheme"'
check "no per-user OMZ custom dir" bash -c '! test -d "${_ZDOTDIR}/custom"'
check "no per-user OMB custom dir" bash -c '! test -d "${_HOME}/.config/bash/custom"'

# --- System config files still deployed ---
check "/etc/profile exists" test -f /etc/profile
check "system bashrc exists" bash -c 'test -f /etc/bash.bashrc || test -f /etc/bashrc || test -f /etc/bash/bashrc'

reportResults
