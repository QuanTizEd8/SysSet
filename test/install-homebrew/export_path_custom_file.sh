#!/bin/bash
# export_path_custom_file: export_path="/tmp/custom-brew.sh"
# Verifies that the shellenv block is written ONLY to the specified custom
# file and that no system-wide files (/etc/profile.d/brew.sh, bash.bashrc,
# zshenv) are touched.
set -e

source dev-container-features-test-lib

_BREW=/home/linuxbrew/.linuxbrew/bin/brew

# --- brew installed and functional ---
check "brew binary installed"                     test -f "$_BREW"
check "brew binary is executable"                test -x "$_BREW"
echo "=== brew --version ==="; "$_BREW" --version 2>&1 || echo "(failed)"
check "brew --version succeeds"                   "$_BREW" --version

# --- shellenv block written to the custom file ---
echo "=== /tmp/custom-brew.sh ==="; cat /tmp/custom-brew.sh 2>/dev/null || echo "(missing)"
check "custom shellenv file written"              test -f /tmp/custom-brew.sh
check "custom file has begin marker"              grep -qF '# >>> brew shellenv (install-homebrew) >>>' /tmp/custom-brew.sh
check "custom file has end marker"               grep -qF '# <<< brew shellenv (install-homebrew) <<<' /tmp/custom-brew.sh
check "custom file has shellenv eval"             grep -qF 'brew shellenv' /tmp/custom-brew.sh

# --- system-wide files NOT touched ---
echo "=== /etc/profile.d/brew.sh ==="; cat /etc/profile.d/brew.sh 2>/dev/null || echo "(missing — expected)"
check "profile.d/brew.sh NOT written"             bash -c '! test -f /etc/profile.d/brew.sh'
check "bash.bashrc has NO brew marker"            bash -c '! grep -qF "brew shellenv (install-homebrew)" /etc/bash.bashrc 2>/dev/null'
check "zshenv has NO brew marker"                 bash -c '! grep -qF "brew shellenv (install-homebrew)" /etc/zsh/zshenv 2>/dev/null && ! grep -qF "brew shellenv (install-homebrew)" /etc/zshenv 2>/dev/null'

reportResults
