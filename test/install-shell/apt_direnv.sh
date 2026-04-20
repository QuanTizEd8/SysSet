#!/bin/bash
# Verifies direnv is installed and shell hooks are injected into per-user config.
set -e

source dev-container-features-test-lib

_ZSHTHEME="/root/.config/zsh/zshtheme"
_BASHTHEME="/root/.config/bash/bashtheme"

# --- direnv binary ---
check "direnv on PATH" command -v direnv
check "direnv responds to --version" direnv --version

# --- per-user zsh hook ---
check "zshtheme written" test -f "$_ZSHTHEME"
check "direnv hook in zshtheme" grep -qF 'direnv hook zsh' "$_ZSHTHEME"

# --- per-user bash hook ---
check "bashtheme written" test -f "$_BASHTHEME"
check "direnv hook in bashtheme" grep -qF 'direnv hook bash' "$_BASHTHEME"

reportResults
