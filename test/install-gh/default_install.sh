#!/bin/bash
# Default installation on Ubuntu: all defaults (method=repos).
# Verifies gh is installed, callable, bash and zsh completions are present.
set -e

source dev-container-features-test-lib

# --- binary present and callable ---
check "gh binary installed" command -v gh
check "gh binary is executable" bash -c 'gh --version > /dev/null 2>&1'

# --- binary is callable ---
echo "=== gh --version ==="
gh --version 2>&1 || echo "(failed)"
check "gh --version succeeds" gh --version

# --- completions installed (bash) ---
echo "=== /etc/bash_completion.d/gh ==="
head -n 5 /etc/bash_completion.d/gh 2> /dev/null || echo "(missing)"
check "bash completion file exists" test -f /etc/bash_completion.d/gh
check "bash completion file is non-empty" test -s /etc/bash_completion.d/gh

# --- completions installed (zsh) ---
# The feature (as root, debian/ubuntu) writes to /etc/zsh/completions/_gh.
# Secondary: broader search covers any package-installed completions.
echo "=== zsh completions search ==="
find /etc/zsh /usr/local/share/zsh /usr/share/zsh /usr/local/share /usr/share \
  -name "_gh" 2> /dev/null || echo "(none found)"
check "zsh completion file exists" bash -c \
  'test -f /etc/zsh/completions/_gh || \
   find /etc/zsh /usr/local/share/zsh /usr/share/zsh /usr/local/share /usr/share \
     -name "_gh" 2>/dev/null | grep -q .'

reportResults
