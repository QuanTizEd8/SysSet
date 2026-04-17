#!/bin/bash
# method=binary, prefix=/root/gh, symlink=true.
# $prefix is under root's home directory (/root per /etc/passwd), so a
# user-scoped symlink is created at $HOME/.local/bin/gh -> $prefix/bin/gh.
# No system-wide /usr/local/bin/gh symlink is created.
set -e

source dev-container-features-test-lib

# --- binary installed at user home prefix ---
check "gh binary at /root/gh/bin/gh" test -f /root/gh/bin/gh
check "gh binary is executable" test -x /root/gh/bin/gh

# --- user-scoped symlink created (prefix is under /root per /etc/passwd) ---
check "/root/.local/bin/gh symlink exists" test -L /root/.local/bin/gh
check "symlink target is /root/gh/bin/gh" bash -c '[ "$(readlink /root/.local/bin/gh)" = "/root/gh/bin/gh" ]'
check "gh callable via symlink" /root/.local/bin/gh --version

# --- no system-wide symlink created ---
check "no /usr/local/bin/gh symlink" bash -c '! test -e /usr/local/bin/gh'

reportResults
