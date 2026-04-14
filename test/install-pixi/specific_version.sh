#!/bin/bash
# version=0.41.0: install a specific pinned version.
# Verifies pixi reports exactly 0.41.0.
set -e

source dev-container-features-test-lib

# --- binary installed and callable ---
check "pixi binary installed" test -f /usr/local/bin/pixi
check "pixi binary is executable" test -x /usr/local/bin/pixi
check "pixi --version succeeds" /usr/local/bin/pixi --version

# --- version matches requested pin ---
echo "=== pixi --version ==="
/usr/local/bin/pixi --version 2>&1 || echo "(failed)"
check "pixi version is 0.41.0" bash -c '[ "$(/usr/local/bin/pixi --version 2>/dev/null | awk "{print \$NF}")" = "0.41.0" ]'

reportResults
