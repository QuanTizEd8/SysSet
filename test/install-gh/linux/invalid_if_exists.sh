#!/usr/bin/env bash
# Verify that passing an unknown if_exists value causes the installer to exit non-zero.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required}"
# shellcheck source=test/lib/assert.sh
source "${REPO_ROOT}/test/lib/assert.sh"

fail_check "invalid if_exists value exits non-zero" \
  bash "${REPO_ROOT}/src/install-gh/install.bash" --if_exists invalid

reportResults
