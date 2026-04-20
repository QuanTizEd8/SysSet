#!/bin/bash
# Verifies fzf is installed from GitHub Releases and shell hooks are injected
# into per-user config.
set -e

source dev-container-features-test-lib

_ZSHTHEME="/root/.config/zsh/zshtheme"
_BASHTHEME="/root/.config/bash/bashtheme"

# --- fzf binary ---
check "fzf binary installed at prefix" test -x /usr/local/bin/fzf
check "fzf on PATH" command -v fzf
check "fzf responds to --version" fzf --version

# --- per-user zsh hook ---
check "zshtheme written" test -f "$_ZSHTHEME"
check "fzf hook in zshtheme" grep -qF 'fzf --zsh' "$_ZSHTHEME"

# --- per-user bash hook ---
check "bashtheme written" test -f "$_BASHTHEME"
check "fzf hook in bashtheme" grep -qF 'fzf --bash' "$_BASHTHEME"

reportResults
