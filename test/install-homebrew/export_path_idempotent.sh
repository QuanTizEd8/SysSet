#!/bin/bash
# export_path_idempotent: shellenv blocks are pre-written in the image
# (see Dockerfile).  The feature re-runs with default options (if_exists=skip)
# and must UPDATE each block in-place — the begin marker must appear exactly
# once per file (no duplicate appends).
set -e

source dev-container-features-test-lib

_BREW=/home/linuxbrew/.linuxbrew/bin/brew

# --- brew is functional ---
check "brew binary installed"                         test -f "$_BREW"
check "brew --version succeeds"                       "$_BREW" --version

# --- blocks are present in each file ---
check "profile.d/brew.sh has begin marker"            grep -qF '# >>> brew shellenv (install-homebrew) >>>' /etc/profile.d/brew.sh
check "bash.bashrc has begin marker"                  grep -qF '# >>> brew shellenv (install-homebrew) >>>' /etc/bash.bashrc
check "zshenv has begin marker"                       grep -qF '# >>> brew shellenv (install-homebrew) >>>' /etc/zsh/zshenv

# --- exactly one copy of the block per file (no duplicates) ---
echo "=== /etc/profile.d/brew.sh ===";  cat /etc/profile.d/brew.sh 2>/dev/null || echo "(missing)"
echo "=== /etc/bash.bashrc (tail) ==="; tail -15 /etc/bash.bashrc 2>/dev/null || echo "(missing)"
echo "=== /etc/zsh/zshenv ===";        cat /etc/zsh/zshenv 2>/dev/null || echo "(missing)"

check "profile.d/brew.sh has exactly one begin marker" \
    bash -c '[ "$(grep -cF "# >>> brew shellenv (install-homebrew) >>>" /etc/profile.d/brew.sh)" -eq 1 ]'
check "bash.bashrc has exactly one begin marker" \
    bash -c '[ "$(grep -cF "# >>> brew shellenv (install-homebrew) >>>" /etc/bash.bashrc)" -eq 1 ]'
check "zshenv has exactly one begin marker" \
    bash -c '[ "$(grep -cF "# >>> brew shellenv (install-homebrew) >>>" /etc/zsh/zshenv)" -eq 1 ]'

# --- the content references the correct brew prefix ---
check "profile.d block references correct brew prefix" \
    grep -qF '/home/linuxbrew/.linuxbrew/bin/brew' /etc/profile.d/brew.sh
check "bash.bashrc block references correct brew prefix" \
    grep -qF '/home/linuxbrew/.linuxbrew/bin/brew' /etc/bash.bashrc
check "zshenv block references correct brew prefix" \
    grep -qF '/home/linuxbrew/.linuxbrew/bin/brew' /etc/zsh/zshenv

reportResults
