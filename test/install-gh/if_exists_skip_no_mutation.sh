#!/bin/bash
# if_exists=skip should exit before any installer-side mutation.
# This image has gh preinstalled but curl intentionally removed. If the feature
# truly makes no changes when skipping, curl must stay absent.
set -e

source dev-container-features-test-lib

check "gh binary still present at /usr/local/bin/gh" test -f /usr/local/bin/gh
check "gh binary is still executable" test -x /usr/local/bin/gh
check "gh version is still 2.67.0" bash -c \
  '[ "$(gh --version 2>/dev/null | head -1 | awk "{print \$3}")" = "2.67.0" ]'
check "curl remains absent when install is skipped" bash -c '! command -v curl >/dev/null 2>&1'

reportResults
