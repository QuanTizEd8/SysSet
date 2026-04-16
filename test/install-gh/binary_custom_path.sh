#!/bin/bash
# method=binary, prefix=/opt/gh, symlink=true:
# Binary at /opt/gh/bin/gh, symlink at /usr/local/bin/gh pointing to it.
set -e

source dev-container-features-test-lib

# --- binary installed at custom path ---
echo "=== /opt/gh/bin/gh ==="
ls -la /opt/gh/bin/gh 2> /dev/null || echo "(missing)"
check "gh binary at /opt/gh/bin/gh" test -f /opt/gh/bin/gh
check "gh binary at custom path is executable" test -x /opt/gh/bin/gh
check "gh --version via custom path" /opt/gh/bin/gh --version

# --- symlink created at /usr/local/bin/gh ---
echo "=== /usr/local/bin/gh symlink ==="
ls -la /usr/local/bin/gh 2> /dev/null || echo "(missing)"
check "symlink exists at /usr/local/bin/gh" test -L /usr/local/bin/gh
check "symlink resolves to /opt/gh/bin/gh" bash -c \
  '[ "$(readlink -f /usr/local/bin/gh)" = "/opt/gh/bin/gh" ]'
check "gh callable via PATH" command -v gh
check "gh --version succeeds via symlink" gh --version

reportResults
