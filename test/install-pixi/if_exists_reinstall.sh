#!/bin/bash
# if_exists=reinstall: pixi is pre-installed (see Dockerfile). The feature
# removes the existing binary and installs a fresh copy.
set -e

source dev-container-features-test-lib

# --- pixi is present and functional after reinstall ---
check "pixi binary present at /usr/local/bin/pixi" test -f /usr/local/bin/pixi
check "pixi binary is executable" test -x /usr/local/bin/pixi

echo "=== pixi --version ==="
/usr/local/bin/pixi --version 2>&1 || echo "(failed)"
check "pixi --version succeeds" /usr/local/bin/pixi --version

# --- no stale installer artifacts ---
check "installer dir cleaned up" bash -c '! test -f /tmp/pixi-installer/pixi-*.tar.gz 2>/dev/null'

reportResults
