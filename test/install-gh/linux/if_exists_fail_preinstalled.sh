#!/usr/bin/env bash
# Verify that if_exists=fail exits non-zero when gh is already installed.
# SETUP_CMD (in if_exists_fail_preinstalled.conf) places a stub gh binary.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required}"
# shellcheck source=test/lib/assert.sh
source "${REPO_ROOT}/test/lib/assert.sh"

# Confirm the stub is pre-installed by SETUP_CMD.
check "gh stub pre-installed by setup" command -v gh
check "gh stub reports a version" bash -c 'gh --version | grep -qE "gh version [0-9]"'

fail_check "if_exists=fail with pre-installed gh exits non-zero" \
  bash "${REPO_ROOT}/src/install-gh/install.bash" \
  --if_exists fail

reportResults
