#!/bin/bash
# Default installation on Ubuntu: all defaults (root → /usr/local/bin, export_path=auto no-op).
# Verifies pixi is installed, callable, and that no unnecessary PATH or PIXI_HOME
# blocks are written (bin_dir=/usr/local/bin is already on PATH).
set -e

source dev-container-features-test-lib

# --- binary installed ---
check "pixi binary installed at /usr/local/bin/pixi" test -f /usr/local/bin/pixi
check "pixi binary is executable" test -x /usr/local/bin/pixi

# --- binary is callable ---
echo "=== pixi --version ==="
/usr/local/bin/pixi --version 2>&1 || echo "(failed)"
check "pixi --version succeeds" /usr/local/bin/pixi --version

# --- no PATH block written (bin_dir=/usr/local/bin, no-op) ---
check "no profile.d pixi_bin_path.sh written" bash -c '! test -f /etc/profile.d/pixi_bin_path.sh'

# --- no PIXI_HOME block written (home_dir is empty) ---
check "no profile.d pixi_home.sh written" bash -c '! test -f /etc/profile.d/pixi_home.sh'

# --- no installer artifacts left ---
check "installer dir cleaned up" bash -c '! test -f /tmp/pixi-installer/pixi-*.tar.gz 2>/dev/null'

reportResults
