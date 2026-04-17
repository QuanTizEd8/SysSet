#!/bin/bash
# prefix=/opt/pixi, symlink=true, running as non-root (vscode).
# The installer runs as root (devcontainer build), so the system-wide symlink
# /usr/local/bin/pixi is created. No user-scoped symlink is expected.
set -e

source dev-container-features-test-lib

# --- binary installed at custom path ---
check "pixi binary at /opt/pixi/bin/pixi" test -f /opt/pixi/bin/pixi
check "pixi binary is executable" test -x /opt/pixi/bin/pixi

# --- system-wide symlink created (installer runs as root) ---
check "/usr/local/bin/pixi symlink exists" test -L /usr/local/bin/pixi
check "symlink target is /opt/pixi/bin/pixi" bash -c '[ "$(readlink /usr/local/bin/pixi)" = "/opt/pixi/bin/pixi" ]'
check "pixi callable via symlink" /usr/local/bin/pixi --version

# --- no user-scoped symlink created ---
check "no \$HOME/.pixi/bin/pixi symlink" bash -c '! test -e /home/vscode/.pixi/bin/pixi'

reportResults
