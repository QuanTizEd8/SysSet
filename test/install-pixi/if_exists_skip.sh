#!/bin/bash
# if_exists=skip: pixi is pre-installed in the image (see Dockerfile).
# The feature detects the existing binary and skips reinstalling,
# continuing to post-install steps (PATH export, symlink, etc.).
set -e

source dev-container-features-test-lib

# --- original pixi installation is intact ---
check "pixi binary still present at /usr/local/bin/pixi" test -f /usr/local/bin/pixi
check "pixi binary is still executable" test -x /usr/local/bin/pixi

# --- pixi is still functional ---
echo "=== pixi --version ==="
/usr/local/bin/pixi --version 2>&1 || echo "(failed)"
check "pixi --version succeeds" /usr/local/bin/pixi --version

reportResults
