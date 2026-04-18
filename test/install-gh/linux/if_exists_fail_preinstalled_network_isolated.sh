#!/usr/bin/env bash
# Verify that if_exists=fail with a pre-installed gh stub exits non-zero even
# when the network is blocked — the existence check happens before any network call.
# The base image (built by run-linux.sh) provides the required apt packages.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required}"
# shellcheck source=test/lib/assert.sh
source "${REPO_ROOT}/test/lib/assert.sh"

check "gh stub pre-installed by setup" command -v gh

fail_check "if_exists=fail (network-isolated) with pre-installed gh exits non-zero" \
  bash "${REPO_ROOT}/src/install-gh/install.bash" \
  --if_exists fail

reportResults
