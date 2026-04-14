#!/bin/bash
# version=0.41.0 + if_exists=uninstall, with pixi 0.41.0 pre-installed (see Dockerfile).
# The version-match check fires before if_exists dispatch, so uninstall is never
# triggered. pixi is unchanged and post-install steps still run.
set -e

source dev-container-features-test-lib

# --- pixi binary is still present (not removed) ---
check "pixi binary still present" test -f /usr/local/bin/pixi
check "pixi binary is executable" test -x /usr/local/bin/pixi

# --- version is unchanged at 0.41.0 ---
echo "=== pixi --version ==="
/usr/local/bin/pixi --version 2>&1 || echo "(failed)"
check "pixi --version succeeds" /usr/local/bin/pixi --version
check "pixi version is still 0.41.0" bash -c '[ "$(/usr/local/bin/pixi --version 2>/dev/null | awk "{print \$NF}")" = "0.41.0" ]'

reportResults
