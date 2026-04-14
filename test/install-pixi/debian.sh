#!/bin/bash
# Default installation on Debian: same as default_install but on Debian:latest.
# Verifies pixi is installed and callable on a Debian base image.
set -e

source dev-container-features-test-lib

# --- binary installed ---
check "pixi binary installed" test -f /usr/local/bin/pixi
check "pixi binary is executable" test -x /usr/local/bin/pixi

# --- binary is callable ---
echo "=== pixi --version ==="
/usr/local/bin/pixi --version 2>&1 || echo "(failed)"
check "pixi --version succeeds" /usr/local/bin/pixi --version

# --- no unnecessary PATH block written ---
check "no profile.d pixi_bin_path.sh written" bash -c '! test -f /etc/profile.d/pixi_bin_path.sh'

reportResults
