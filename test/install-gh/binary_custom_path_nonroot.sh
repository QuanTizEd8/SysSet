#!/bin/bash
# method=binary, prefix=/opt/gh, symlink=true, running as non-root (vscode).
# The installer runs as root (devcontainer build), so the system-wide symlink
# /usr/local/bin/gh is created. No user-scoped symlink is expected.
set -e

source dev-container-features-test-lib

# --- binary installed at custom path ---
check "gh binary at /opt/gh/bin/gh" test -f /opt/gh/bin/gh
check "gh binary is executable" test -x /opt/gh/bin/gh
check "gh --version via custom path" /opt/gh/bin/gh --version

# --- system-wide symlink created (installer runs as root) ---
check "/usr/local/bin/gh symlink exists" test -L /usr/local/bin/gh
check "symlink target is /opt/gh/bin/gh" bash -c '[ "$(readlink /usr/local/bin/gh)" = "/opt/gh/bin/gh" ]'

# --- no user-scoped symlink created ---
check "no \$HOME/.local/bin/gh symlink" bash -c '! test -e /home/vscode/.local/bin/gh'

reportResults
