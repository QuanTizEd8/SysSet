#!/bin/bash
# method=binary, keep_installer=true, installer_dir=/tmp/gh-debug:
# The downloaded archive and checksums file must remain in /tmp/gh-debug after install.
set -e

source dev-container-features-test-lib

# --- gh installed and functional ---
check "gh binary installed" test -f /usr/local/bin/gh
check "gh --version succeeds" gh --version

# --- installer_dir still exists ---
echo "=== /tmp/gh-debug/ contents ==="
ls -la /tmp/gh-debug/ 2> /dev/null || echo "(directory missing)"
check "installer_dir exists" test -d /tmp/gh-debug

# --- archive preserved ---
check "gh archive preserved in installer_dir" bash -c \
  'ls /tmp/gh-debug/gh_*.tar.gz 2>/dev/null | grep -q .'

# --- checksums file preserved ---
check "checksums file preserved in installer_dir" bash -c \
  'test -f /tmp/gh-debug/checksums.txt'

reportResults
