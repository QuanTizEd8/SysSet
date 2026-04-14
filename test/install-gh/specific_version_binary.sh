#!/bin/bash
# version=2.67.0 + method=binary: install a specific pinned version via binary download.
# Verifies the binary reports exactly 2.67.0.
set -e

source dev-container-features-test-lib

# --- binary present and executable ---
check "gh binary installed at /usr/local/bin/gh" test -f /usr/local/bin/gh
check "gh binary is executable" test -x /usr/local/bin/gh

# --- binary is callable ---
echo "=== gh --version ==="
gh --version 2>&1 || echo "(failed)"
check "gh --version succeeds" gh --version

# --- version matches requested pin ---
check "gh version is exactly 2.67.0" bash -c \
  '[ "$(gh --version 2>/dev/null | head -1 | awk "{print \$3}")" = "2.67.0" ]'

# --- checksum was verified (indirectly: binary installed cleanly) ---
# If checksum mismatch occurred, install would have aborted before reaching here.

reportResults
