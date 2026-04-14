#!/bin/bash
# if_exists=update on a fresh image (no pre-existing pixi):
# The feature should install pixi normally (no existing binary to update),
# then a self-update yields the latest version.
set -e

source dev-container-features-test-lib

# --- pixi is installed and functional ---
check "pixi binary installed at /usr/local/bin/pixi" test -f /usr/local/bin/pixi
check "pixi binary is executable" test -x /usr/local/bin/pixi

echo "=== pixi --version ==="
/usr/local/bin/pixi --version 2>&1 || echo "(failed)"
check "pixi --version succeeds" /usr/local/bin/pixi --version

reportResults
