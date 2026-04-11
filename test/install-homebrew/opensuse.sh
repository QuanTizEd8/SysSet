#!/bin/bash
# opensuse: all defaults on openSUSE Leap (Zypper).
# Verifies that Homebrew installs under /home/linuxbrew/.linuxbrew, brew is
# functional, and shellenv blocks are written to the appropriate system-wide
# startup files (Case A: root + Linux).
#
# Platform detection: ID=opensuse-leap, ID_LIKE=suse → no case matches →
# falls back to "debian" default.
#   bashrc: uses first of /etc/bash.bashrc, /etc/bashrc that exists
#   zshenv: /etc/zsh/zshenv (created when absent)
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
check "brew --version reports Homebrew" bash -c '"$_BREW" --version | grep -q Homebrew' _BREW="$_BREW"

# --- shellenv export (Case A: root + Linux) ---
echo "=== /etc/profile.d/brew.sh ==="
cat /etc/profile.d/brew.sh 2> /dev/null || echo "(missing)"
echo "=== /etc/bash.bashrc (tail) ==="
tail -10 /etc/bash.bashrc 2> /dev/null || echo "(missing)"
echo "=== /etc/bashrc (tail) ==="
tail -10 /etc/bashrc 2> /dev/null || echo "(missing)"
echo "=== /etc/zsh/zshenv ==="
cat /etc/zsh/zshenv 2> /dev/null || echo "(missing)"
echo "=== /etc/zshenv ==="
cat /etc/zshenv 2> /dev/null || echo "(missing)"

check "profile.d/brew.sh written" test -f /etc/profile.d/brew.sh
check "profile.d/brew.sh has begin marker" grep -qF '# >>> brew shellenv (install-homebrew) >>>' /etc/profile.d/brew.sh
check "profile.d/brew.sh has shellenv eval" grep -qF 'brew shellenv' /etc/profile.d/brew.sh

# The feature writes to whichever global bashrc file exists first
check "a global bashrc has begin marker" \
  bash -c 'grep -qF "# >>> brew shellenv (install-homebrew) >>>" /etc/bash.bashrc 2>/dev/null || grep -qF "# >>> brew shellenv (install-homebrew) >>>" /etc/bashrc 2>/dev/null'
check "a global bashrc has shellenv eval" \
  bash -c 'grep -qF "brew shellenv" /etc/bash.bashrc 2>/dev/null || grep -qF "brew shellenv" /etc/bashrc 2>/dev/null'

# zshenv — /etc/zsh/zshenv (created) on the "debian" platform fallback
check "a zshenv has begin marker" \
  bash -c 'grep -qF "# >>> brew shellenv (install-homebrew) >>>" /etc/zsh/zshenv 2>/dev/null || grep -qF "# >>> brew shellenv (install-homebrew) >>>" /etc/zshenv 2>/dev/null'
check "a zshenv has shellenv eval" \
  bash -c 'grep -qF "brew shellenv" /etc/zsh/zshenv 2>/dev/null || grep -qF "brew shellenv" /etc/zshenv 2>/dev/null'

# --- login PATH includes linuxbrew ---
echo "=== login PATH ==="
bash -lc 'echo "$PATH"' 2>&1 || echo "(failed)"
check "login PATH includes linuxbrew/bin" bash -lc 'echo "$PATH"' | grep -q '/home/linuxbrew/.linuxbrew/bin'

reportResults
