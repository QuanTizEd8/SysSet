#!/bin/bash
# prefix=/opt/myforge, symlink=true, running as non-root (vscode).
# The installer runs as root (devcontainer build), so the system-wide symlink
# /opt/conda -> /opt/myforge is created. No user-scoped symlink is expected.
set -e

source dev-container-features-test-lib

# --- installation at custom prefix ---
check "conda binary at /opt/myforge/bin/conda" test -f /opt/myforge/bin/conda
check "conda binary is executable" test -x /opt/myforge/bin/conda

# --- system-wide symlink created (installer runs as root) ---
check "/opt/conda symlink exists" test -L /opt/conda
check "symlink target is /opt/myforge" bash -c '[ "$(readlink /opt/conda)" = "/opt/myforge" ]'
check "conda reachable via symlink" test -f /opt/conda/bin/conda

# --- no user-scoped symlink created ---
check "no \$HOME/miniforge3 symlink" bash -c '! test -e /home/vscode/miniforge3'

reportResults
