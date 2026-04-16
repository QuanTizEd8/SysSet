#!/bin/bash
# method=binary, prefix=/opt/gh, symlink=false:
# Binary at /opt/gh/bin/gh; NO symlink should exist at /usr/local/bin/gh.
set -e

source dev-container-features-test-lib

# --- binary installed at custom path ---
echo "=== /opt/gh/bin/gh ==="
ls -la /opt/gh/bin/gh 2> /dev/null || echo "(missing)"
check "gh binary at /opt/gh/bin/gh" test -f /opt/gh/bin/gh
check "gh binary at custom path is executable" test -x /opt/gh/bin/gh
check "gh --version via custom path" /opt/gh/bin/gh --version

# --- no symlink at /usr/local/bin/gh ---
echo "=== /usr/local/bin/gh (should be absent) ==="
ls -la /usr/local/bin/gh 2> /dev/null || echo "(correctly absent)"
check "no symlink at /usr/local/bin/gh" bash -c '! test -e /usr/local/bin/gh'

reportResults
