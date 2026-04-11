#!/bin/bash
# apt_default: all defaults on Ubuntu.
# Verifies that Homebrew is installed under /home/linuxbrew/.linuxbrew,
# brew is executable and reports its version, and shellenv blocks are
# written to all three system-wide startup files (Case A: root + Linux).
set -e

source dev-container-features-test-lib

_BREW=/home/linuxbrew/.linuxbrew/bin/brew

# --- installation directory structure ---
check "linuxbrew prefix directory exists"          test -d /home/linuxbrew/.linuxbrew
check "linuxbrew bin directory exists"             test -d /home/linuxbrew/.linuxbrew/bin
check "brew binary installed"                      test -f "$_BREW"
check "brew binary is executable"                  test -x "$_BREW"

# --- brew is functional ---
echo "=== brew --version ==="; "$_BREW" --version 2>&1 || echo "(failed)"
check "brew --version succeeds"                    "$_BREW" --version
check "brew --version reports Homebrew"            bash -c '"$_BREW" --version | grep -q Homebrew' _BREW="$_BREW"

# --- shellenv export (export_path=auto, Case A: root + Linux) ---
echo "=== /etc/profile.d/brew.sh ===";  cat /etc/profile.d/brew.sh 2>/dev/null || echo "(missing)"
echo "=== /etc/bash.bashrc (tail) ==="; tail -10 /etc/bash.bashrc 2>/dev/null || echo "(missing)"
echo "=== /etc/zsh/zshenv ===";        cat /etc/zsh/zshenv 2>/dev/null || echo "(missing)"

check "profile.d/brew.sh written"                  test -f /etc/profile.d/brew.sh
check "profile.d/brew.sh has begin marker"         grep -qF '# >>> brew shellenv (install-homebrew) >>>' /etc/profile.d/brew.sh
check "profile.d/brew.sh has shellenv eval"        grep -qF 'brew shellenv' /etc/profile.d/brew.sh
check "bash.bashrc has begin marker"               grep -qF '# >>> brew shellenv (install-homebrew) >>>' /etc/bash.bashrc
check "bash.bashrc has shellenv eval"              grep -qF 'brew shellenv' /etc/bash.bashrc
check "zshenv written"                             bash -c 'test -f /etc/zsh/zshenv || test -f /etc/zshenv'
check "zshenv has begin marker"                    bash -c 'grep -qF "# >>> brew shellenv (install-homebrew) >>>" /etc/zsh/zshenv 2>/dev/null || grep -qF "# >>> brew shellenv (install-homebrew) >>>" /etc/zshenv'
check "zshenv has shellenv eval"                   bash -c 'grep -qF "brew shellenv" /etc/zsh/zshenv 2>/dev/null || grep -qF "brew shellenv" /etc/zshenv'

# --- login PATH includes linuxbrew ---
echo "=== login PATH ==="; bash -lc 'echo "$PATH"' 2>&1 || echo "(failed)"
check "login PATH includes linuxbrew/bin"          bash -lc 'echo "$PATH"' | grep -q '/home/linuxbrew/.linuxbrew/bin'

reportResults
