#!/bin/bash
# Verifies that the default installation correctly deploys skel files:
# - .zshenv goes to HOME (so zsh finds it before ZDOTDIR is known)
# - .zshrc, .zprofile, .zlogin go to ZDOTDIR
# - .shellenv, .shellrc, .bash_profile, .bashrc go to HOME
set -e

source dev-container-features-test-lib

_HOME=/root
_ZDOTDIR="${_HOME}/.config/zsh"

# Files that must be in HOME
for _f in .zshenv .shellenv .shellrc .bash_profile .bashrc; do
  check "${_f} in HOME" test -f "${_HOME}/${_f}"
done

# Zsh config files that must be in ZDOTDIR (not HOME)
for _f in .zshrc .zprofile .zlogin; do
  check "${_f} in ZDOTDIR" test -f "${_ZDOTDIR}/${_f}"
  check "${_f} NOT in HOME" bash -c "! test -f '${_HOME}/${_f}'"
done

# .zshenv does NOT go into ZDOTDIR
check ".zshenv NOT in ZDOTDIR" bash -c "! test -f '${_ZDOTDIR}/.zshenv'"

reportResults
