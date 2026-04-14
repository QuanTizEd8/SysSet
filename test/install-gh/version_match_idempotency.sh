#!/bin/bash
# version=2.67.0 + if_exists=fail + gh 2.67.0 pre-installed (see version_match_idempotency/Dockerfile).
# The version-match guard must fire BEFORE if_exists dispatch, so the feature exits 0
# even though if_exists=fail would otherwise abort.
# The binary must remain at 2.67.0 and be functional.
set -e

source dev-container-features-test-lib

# --- original binary is still present ---
check "gh binary still present at /usr/local/bin/gh" test -f /usr/local/bin/gh
check "gh binary is still executable" test -x /usr/local/bin/gh

# --- binary is still functional ---
echo "=== gh --version ==="
gh --version 2>&1 || echo "(failed)"
check "gh --version succeeds" gh --version

# --- version is unchanged at 2.67.0 (feature did not reinstall) ---
check "gh version is still 2.67.0" bash -c \
  '[ "$(gh --version 2>/dev/null | head -1 | awk "{print \$3}")" = "2.67.0" ]'

reportResults
