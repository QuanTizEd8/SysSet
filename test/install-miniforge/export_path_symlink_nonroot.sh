#!/bin/bash
# prefix=/opt/myforge, symlink=true, running as non-root (vscode).
# Verifies miniforge is installed at /opt/myforge and a symlink is created at
# $HOME/miniforge3 -> /opt/myforge.
set -e

source dev-container-features-test-lib

# --- installation at custom prefix ---
check "conda binary at /opt/myforge/bin/conda" test -f /opt/myforge/bin/conda
check "conda binary is executable" test -x /opt/myforge/bin/conda

# --- symlink $HOME/miniforge3 → /opt/myforge ---
check "\$HOME/miniforge3 exists" test -e /home/vscode/miniforge3
check "\$HOME/miniforge3 is a symlink" test -L /home/vscode/miniforge3
check "symlink target is /opt/myforge" bash -c '[ "$(readlink /home/vscode/miniforge3)" = "/opt/myforge" ]'
check "conda reachable via symlink" test -f /home/vscode/miniforge3/bin/conda

# --- no system-wide symlink created (non-root cannot write /opt/conda) ---
check "no /opt/conda symlink created" bash -c '! test -L /opt/conda'
check "no /opt/conda directory created" bash -c '! test -e /opt/conda'

reportResults
