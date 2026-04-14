#!/bin/bash
# bin_dir=/opt/pixi-bin, symlink=true (as root):
# Verifies pixi installed to custom dir AND a symlink is created at
# /usr/local/bin/pixi pointing to the custom-dir binary.
set -e

source dev-container-features-test-lib

# --- binary installed at custom path ---
check "pixi binary installed at /opt/pixi-bin/pixi" test -f /opt/pixi-bin/pixi
check "pixi binary is executable" test -x /opt/pixi-bin/pixi

# --- symlink created at /usr/local/bin/pixi ---
check "symlink exists at /usr/local/bin/pixi" test -L /usr/local/bin/pixi
check "symlink points to /opt/pixi-bin/pixi" bash -c '[ "$(readlink /usr/local/bin/pixi)" = "/opt/pixi-bin/pixi" ]'
check "symlink is callable" /usr/local/bin/pixi --version

# --- PATH block written (bin_dir != /usr/local/bin) ---
check "profile.d pixi_bin_path.sh written" test -f /etc/profile.d/pixi_bin_path.sh
check "profile.d script exports /opt/pixi-bin" grep -Fq '/opt/pixi-bin' /etc/profile.d/pixi_bin_path.sh

reportResults
