#!/bin/bash
# Default installation on Ubuntu: all defaults (method=repos, binary at /usr/local/bin/gh).
# Verifies gh is installed, callable, bash and zsh completions are present.
set -e

source dev-container-features-test-lib

# --- binary present and executable ---
check "gh binary installed at /usr/local/bin/gh" test -f /usr/local/bin/gh
check "gh binary is executable" test -x /usr/local/bin/gh

# --- binary is callable ---
echo "=== gh --version ==="
gh --version 2>&1 || echo "(failed)"
check "gh --version succeeds" gh --version

# --- completions installed (bash) ---
echo "=== /etc/bash_completion.d/gh ==="
cat /etc/bash_completion.d/gh 2> /dev/null | head -5 || echo "(missing)"
check "bash completion file exists" test -f /etc/bash_completion.d/gh
check "bash completion file is non-empty" test -s /etc/bash_completion.d/gh

# --- completions installed (zsh) ---
# zsh completion is placed under the system zsh site-functions directory
echo "=== zsh completions search ==="
find /usr/local/share/zsh /usr/share/zsh /usr/local/share /usr/share \
  -name "_gh" 2> /dev/null || echo "(none found)"
check "zsh completion file exists" bash -c \
  'find /usr/local/share/zsh /usr/share/zsh /usr/local/share /usr/share \
    -name "_gh" 2>/dev/null | grep -q .'

reportResults
