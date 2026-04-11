#!/bin/bash
# fedora: all defaults on Fedora (DNF).
# Verifies that Homebrew installs under /home/linuxbrew/.linuxbrew, brew is
# functional, and shellenv blocks are written to the Fedora-specific system-wide
# startup files (Case A: root + Linux).
#
# Platform detection: ID=fedora → platform="rhel"
#   bashrc: /etc/bashrc  (existing file, preferred over platform default)
#   zshenv: /etc/zshenv  (_platform_zshenv "rhel")
set -e

source dev-container-features-test-lib

_BREW=/home/linuxbrew/.linuxbrew/bin/brew

# --- installation directory structure ---
check "linuxbrew prefix directory exists" test -d /home/linuxbrew/.linuxbrew
check "linuxbrew bin directory exists" test -d /home/linuxbrew/.linuxbrew/bin
check "brew binary installed" test -f "$_BREW"
check "brew binary is executable" test -x "$_BREW"

# --- brew is functional ---
echo "=== brew --version ==="
"$_BREW" --version 2>&1 || echo "(failed)"
check "brew --version succeeds" "$_BREW" --version
check "brew --version reports Homebrew" bash -c '"$1" --version | grep -q Homebrew' -- "$_BREW"

# --- shellenv export (Case A: root + Linux) ---
# profile.d — login shells
echo "=== /etc/profile.d/brew.sh ==="
cat /etc/profile.d/brew.sh 2> /dev/null || echo "(missing)"
# global bashrc — /etc/bashrc on RHEL/Fedora
echo "=== /etc/bashrc (tail) ==="
tail -10 /etc/bashrc 2> /dev/null || echo "(missing)"
# zshenv — /etc/zshenv on RHEL/Fedora
echo "=== /etc/zshenv ==="
cat /etc/zshenv 2> /dev/null || echo "(missing)"

check "profile.d/brew.sh written" test -f /etc/profile.d/brew.sh
check "profile.d/brew.sh has begin marker" grep -qF '# >>> brew shellenv (install-homebrew) >>>' /etc/profile.d/brew.sh
check "profile.d/brew.sh has shellenv eval" grep -qF 'brew shellenv' /etc/profile.d/brew.sh

check "bashrc has begin marker" grep -qF '# >>> brew shellenv (install-homebrew) >>>' /etc/bashrc
check "bashrc has shellenv eval" grep -qF 'brew shellenv' /etc/bashrc

check "zshenv written" test -f /etc/zshenv
check "zshenv has begin marker" grep -qF '# >>> brew shellenv (install-homebrew) >>>' /etc/zshenv
check "zshenv has shellenv eval" grep -qF 'brew shellenv' /etc/zshenv

# --- login PATH includes linuxbrew ---
echo "=== login PATH ==="
bash -lc 'echo "$PATH"' 2>&1 || echo "(failed)"
check "login PATH includes linuxbrew/bin" bash -lc 'echo "$PATH"' | grep -q '/home/linuxbrew/.linuxbrew/bin'

reportResults
