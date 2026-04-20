#!/bin/bash
# Verifies that bash-completion and zsh-completions can be individually disabled.
set -e

source dev-container-features-test-lib

# --- completion packages absent ---
check "bash-completion not installed" bash -c '! dpkg -s bash-completion >/dev/null 2>&1'
check "zsh-completions tree absent" bash -c '! test -d /usr/local/share/zsh-completions'
check "zsh-completions fpath not wired in system zshrc" bash -c '! grep -qF "/usr/local/share/zsh-completions/src" /etc/zsh/zshrc'

reportResults
