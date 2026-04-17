#!/bin/bash
# prefix=/root/pixi, symlink=true.
# $prefix is under root's home directory (/root per /etc/passwd), so a
# user-scoped symlink is created at $HOME/.pixi/bin/pixi -> $prefix/bin/pixi.
# No system-wide /usr/local/bin/pixi symlink is created.
set -e

source dev-container-features-test-lib

# --- binary installed at user home prefix ---
check "pixi binary at /root/pixi/bin/pixi" test -f /root/pixi/bin/pixi
check "pixi binary is executable" test -x /root/pixi/bin/pixi

# --- user-scoped symlink created (prefix is under /root per /etc/passwd) ---
check "/root/.pixi/bin/pixi symlink exists" test -L /root/.pixi/bin/pixi
check "symlink target is /root/pixi/bin/pixi" bash -c '[ "$(readlink /root/.pixi/bin/pixi)" = "/root/pixi/bin/pixi" ]'
check "pixi callable via symlink" /root/.pixi/bin/pixi --version

# --- no system-wide symlink created ---
check "no /usr/local/bin/pixi symlink" bash -c '! test -e /usr/local/bin/pixi'

reportResults
