#!/bin/bash
# Verifies bash-completion and zsh-completions are installed by default,
# and that direnv and fzf are not installed (default: false).
set -e

source dev-container-features-test-lib

# --- bash-completion ---
check "bash-completion package installed" bash -c 'dpkg -s bash-completion >/dev/null 2>&1'
check "bash-completion main script exists" test -f /usr/share/bash-completion/bash_completion

# --- zsh-completions ---
check "zsh-completions package installed" bash -c 'dpkg -s zsh-completions >/dev/null 2>&1'

# --- direnv and fzf not installed by default ---
check "direnv not installed by default" bash -c '! command -v direnv'
check "fzf not installed by default" bash -c '! command -v fzf'

reportResults
