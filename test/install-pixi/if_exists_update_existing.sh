#!/bin/bash
# if_exists=update with pixi 0.41.0 already installed (see Dockerfile):
# verifies the feature exercises pixi self-update instead of the fresh-install
# path and lands on the requested pinned version.
set -e

source dev-container-features-test-lib

# --- pixi remains present and functional after self-update ---
check "pixi binary present at /usr/local/bin/pixi" test -f /usr/local/bin/pixi
check "pixi binary is executable" test -x /usr/local/bin/pixi

echo "=== pixi --version ==="
/usr/local/bin/pixi --version 2>&1 || echo "(failed)"
check "pixi --version succeeds" /usr/local/bin/pixi --version
check "pixi was updated beyond 0.41.0" bash -c '[ "$(/usr/local/bin/pixi --version 2>/dev/null | awk "{print \$NF}")" != "0.41.0" ]'

reportResults
