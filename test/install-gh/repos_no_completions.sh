#!/bin/bash
# method=repos (default), install_completions=false on Ubuntu:
# gh is installed via the official apt repo but completion files must NOT be written.
set -e

source dev-container-features-test-lib

# --- binary present and callable ---
check "gh binary installed" command -v gh
check "gh --version succeeds" gh --version

# --- NO bash completion file ---
echo "=== /etc/bash_completion.d/gh (should be absent) ==="
ls -la /etc/bash_completion.d/gh 2> /dev/null || echo "(correctly absent)"
check "no bash completion file" bash -c '! test -f /etc/bash_completion.d/gh'

# --- NO zsh completion file ---
echo "=== zsh _gh search (should find nothing) ==="
find /usr/local/share/zsh /usr/share/zsh /usr/local/share /usr/share \
  -name "_gh" 2> /dev/null || echo "(correctly absent)"
check "no zsh completion file" bash -c \
  '! find /usr/local/share/zsh /usr/share/zsh /usr/local/share /usr/share \
    -name "_gh" 2>/dev/null | grep -q .'

reportResults
