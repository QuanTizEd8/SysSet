#!/bin/bash
# debian: all defaults on Debian.
# Verifies brew installs successfully on Debian (apt+dpkg package manager)
# and that the brew binary is functional.
set -e

source dev-container-features-test-lib

_BREW=/home/linuxbrew/.linuxbrew/bin/brew

# --- installation directory structure ---
check "linuxbrew prefix directory exists"    test -d /home/linuxbrew/.linuxbrew
check "brew binary installed"               test -f "$_BREW"
check "brew binary is executable"           test -x "$_BREW"

# --- brew is functional ---
echo "=== brew --version ==="; "$_BREW" --version 2>&1 || echo "(failed)"
check "brew --version succeeds"             "$_BREW" --version
check "brew --version reports Homebrew"     bash -c '"$_BREW" --version | grep -q Homebrew' _BREW="$_BREW"

# --- shellenv export written on Debian (Case A) ---
check "profile.d/brew.sh written"          test -f /etc/profile.d/brew.sh
check "profile.d/brew.sh has marker"       grep -qF '# >>> brew shellenv (install-homebrew) >>>' /etc/profile.d/brew.sh

reportResults
