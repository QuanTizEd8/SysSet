#!/bin/bash
# export_path_disabled: export_path="" skips all shellenv writes.
# Verifies that brew installs successfully but no shellenv blocks are
# written to any shell startup file.
set -e

source dev-container-features-test-lib

_BREW=/home/linuxbrew/.linuxbrew/bin/brew

# --- brew installed and functional ---
check "brew binary installed" test -f "$_BREW"
check "brew binary is executable" test -x "$_BREW"
echo "=== brew --version ==="
"$_BREW" --version 2>&1 || echo "(failed)"
check "brew --version succeeds" "$_BREW" --version

# --- no shellenv blocks written anywhere ---
echo "=== /etc/profile.d/brew.sh ==="
cat /etc/profile.d/brew.sh 2> /dev/null || echo "(missing — expected)"
echo "=== /etc/bash.bashrc (tail) ==="
tail -5 /etc/bash.bashrc 2> /dev/null || echo "(missing)"
echo "=== /etc/zsh/zshenv ==="
cat /etc/zsh/zshenv 2> /dev/null || echo "(missing)"

check "profile.d/brew.sh NOT written" bash -c '! test -f /etc/profile.d/brew.sh'
check "bash.bashrc has NO brew marker" bash -c '! grep -qF "brew shellenv (install-homebrew)" /etc/bash.bashrc 2>/dev/null'
check "zshenv has NO brew marker" bash -c '! grep -qF "brew shellenv (install-homebrew)" /etc/zsh/zshenv 2>/dev/null && ! grep -qF "brew shellenv (install-homebrew)" /etc/zshenv 2>/dev/null'

reportResults
