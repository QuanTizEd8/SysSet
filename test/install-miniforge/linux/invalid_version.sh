#!/usr/bin/env bash
# Verify that requesting a nonexistent Miniforge version (0.0.0) fails because
# the GitHub Releases API returns no matching tag.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required}"
# shellcheck source=test/lib/assert.sh
source "${REPO_ROOT}/test/lib/assert.sh"

fail_check "invalid version 0.0.0 exits non-zero" \
  bash "${REPO_ROOT}/src/install-miniforge/install.bash" \
  --version 0.0.0

reportResults
