#!/bin/bash
# Verifies that bash-completion and zsh-completions can be individually disabled.
set -e

source dev-container-features-test-lib

# --- completion packages absent ---
check "bash-completion not installed" bash -c '! dpkg -s bash-completion >/dev/null 2>&1'
check "zsh-completions not installed" bash -c '! dpkg -s zsh-completions >/dev/null 2>&1'

reportResults
