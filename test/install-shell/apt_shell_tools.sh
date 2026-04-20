#!/bin/bash
# Verifies bash-completion and zsh-completions are installed by default,
# and that direnv and fzf are not installed (default: false).
set -e

source dev-container-features-test-lib

# --- bash-completion ---
check "bash-completion package installed" bash -c 'dpkg -s bash-completion >/dev/null 2>&1'
check "bash-completion main script exists" test -f /usr/share/bash-completion/bash_completion

# --- zsh-completions (git install; default apt has no package; OBS builds exist upstream) ---
check "zsh-completions src tree present" bash -c 'test -d /usr/local/share/zsh-completions/src && compgen -G "/usr/local/share/zsh-completions/src/_*" >/dev/null'
check "zsh-completions fpath wired in system zshrc" bash -c 'grep -qF "/usr/local/share/zsh-completions/src" /etc/zsh/zshrc'

# --- direnv and fzf not installed by default ---
check "direnv not installed by default" bash -c '! command -v direnv'
check "fzf not installed by default" bash -c '! command -v fzf'

reportResults
