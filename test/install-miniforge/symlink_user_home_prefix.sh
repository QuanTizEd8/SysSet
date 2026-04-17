#!/bin/bash
# prefix=/root/myforge, symlink=true.
# $prefix is under root's home directory (/root per /etc/passwd), so a
# user-scoped directory symlink is created at $HOME/miniforge3 -> $prefix.
# No system-wide /opt/conda symlink is created.
set -e

source dev-container-features-test-lib

# --- conda installed at user home prefix ---
check "conda installed at /root/myforge" test -d /root/myforge
check "/root/myforge/bin/conda exists" test -f /root/myforge/bin/conda

# --- user-scoped symlink created (prefix is under /root per /etc/passwd) ---
check "/root/miniforge3 symlink exists" test -L /root/miniforge3
check "symlink target is /root/myforge" bash -c '[ "$(readlink /root/miniforge3)" = "/root/myforge" ]'
check "conda reachable via symlink" test -f /root/miniforge3/bin/conda

# --- no system-wide symlink created ---
check "no /opt/conda symlink" bash -c '! test -e /opt/conda'

reportResults
