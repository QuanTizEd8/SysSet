#!/bin/bash
# prefix=/opt/pixi, symlink=true, running as non-root (vscode).
# Verifies pixi is installed at /opt/pixi/bin/pixi and a symlink is created at
# $HOME/.pixi/bin/pixi -> /opt/pixi/bin/pixi.
set -e

source dev-container-features-test-lib

# --- binary installed at custom path ---
check "pixi binary at /opt/pixi/bin/pixi" test -f /opt/pixi/bin/pixi
check "pixi binary is executable" test -x /opt/pixi/bin/pixi

# --- symlink $HOME/.pixi/bin/pixi → /opt/pixi/bin/pixi ---
check "\$HOME/.pixi/bin/pixi exists" test -e /home/vscode/.pixi/bin/pixi
check "\$HOME/.pixi/bin/pixi is a symlink" test -L /home/vscode/.pixi/bin/pixi
check "symlink target is /opt/pixi/bin/pixi" bash -c '[ "$(readlink /home/vscode/.pixi/bin/pixi)" = "/opt/pixi/bin/pixi" ]'
check "pixi callable via symlink" /home/vscode/.pixi/bin/pixi --version

# --- no system-wide symlink created (non-root cannot write /usr/local/bin) ---
check "no symlink at /usr/local/bin/pixi" bash -c '! test -L /usr/local/bin/pixi'

reportResults
