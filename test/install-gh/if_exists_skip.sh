#!/bin/bash
# if_exists=skip: gh 2.67.0 is pre-installed in the image (see if_exists_skip/Dockerfile).
# The feature detects the existing binary and skips reinstalling.
# The original installation must be intact and functional.
set -e

source dev-container-features-test-lib

# --- original installation is intact ---
check "gh binary still present at /usr/local/bin/gh" test -f /usr/local/bin/gh
check "gh binary is still executable" test -x /usr/local/bin/gh

# --- binary is still functional ---
echo "=== gh --version ==="
gh --version 2>&1 || echo "(failed)"
check "gh --version succeeds" gh --version

# --- version is the pre-installed one (not changed by feature) ---
check "gh version is still 2.67.0" bash -c \
  '[ "$(gh --version 2>/dev/null | head -1 | awk "{print \$3}")" = "2.67.0" ]'

reportResults
