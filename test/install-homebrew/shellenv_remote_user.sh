#!/bin/bash
# shellenv_remote_user: add_remote_user=true with remoteUser="vscode".
# Verifies that per-user shellenv blocks are written to vscode's init files
# AND that system-wide blocks are still present (root installs Case A).
set -e

source dev-container-features-test-lib

_BREW=/home/linuxbrew/.linuxbrew/bin/brew
_MARKER='brew shellenv (install-homebrew)'

# --- brew is functional ---
check "brew binary installed" test -f "$_BREW"
check "brew --version succeeds" "$_BREW" --version

# --- system-wide blocks (Case A: root + Linux) ---
check "profile.d/brew.sh has shellenv marker" grep -qF "$_MARKER" /etc/profile.d/brew.sh
check "bash.bashrc has shellenv marker" grep -qF "$_MARKER" /etc/bash.bashrc

# --- per-user blocks for vscode ---
echo "=== /home/vscode init files ==="
for f in .bash_profile .bashrc .zprofile .zshrc; do
  echo "--- $f ---"
  cat "/home/vscode/$f" 2> /dev/null || echo "(missing)"
done

check "vscode .bash_profile has shellenv marker" grep -qF "$_MARKER" /home/vscode/.bash_profile
check "vscode .bashrc has shellenv marker" grep -qF "$_MARKER" /home/vscode/.bashrc
check "vscode .zprofile has shellenv marker" grep -qF "$_MARKER" /home/vscode/.zprofile
check "vscode .zshrc has shellenv marker" grep -qF "$_MARKER" /home/vscode/.zshrc

check "vscode .bash_profile has brew shellenv eval" grep -qF 'brew shellenv' /home/vscode/.bash_profile
check "vscode .bashrc has brew shellenv eval" grep -qF 'brew shellenv' /home/vscode/.bashrc

# --- files owned by vscode ---
check "vscode .bash_profile owned by vscode" bash -c '[ "$(stat -c %U /home/vscode/.bash_profile)" = vscode ]'
check "vscode .bashrc owned by vscode" bash -c '[ "$(stat -c %U /home/vscode/.bashrc)" = vscode ]'

reportResults
