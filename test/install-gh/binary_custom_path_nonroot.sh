#!/bin/bash
# method=binary, prefix=/opt/gh, symlink=true, running as non-root (vscode).
# Verifies gh is installed at /opt/gh/bin/gh and a symlink is created at
# $HOME/.local/bin/gh -> /opt/gh/bin/gh.
set -e

source dev-container-features-test-lib

# --- binary installed at custom path ---
check "gh binary at /opt/gh/bin/gh" test -f /opt/gh/bin/gh
check "gh binary is executable" test -x /opt/gh/bin/gh
check "gh --version via custom path" /opt/gh/bin/gh --version

# --- symlink $HOME/.local/bin/gh → /opt/gh/bin/gh ---
check "\$HOME/.local/bin/gh exists" test -e /home/vscode/.local/bin/gh
check "\$HOME/.local/bin/gh is a symlink" test -L /home/vscode/.local/bin/gh
check "symlink target is /opt/gh/bin/gh" bash -c '[ "$(readlink /home/vscode/.local/bin/gh)" = "/opt/gh/bin/gh" ]'

# --- no system-wide symlink created (non-root cannot write /usr/local/bin) ---
check "no symlink at /usr/local/bin/gh" bash -c '! test -L /usr/local/bin/gh'

reportResults
