#!/usr/bin/env bash
# Verify that if_exists=fail exits non-zero when pixi is already installed.
# SETUP_CMD (in if_exists_fail_preinstalled.conf) places a stub pixi binary.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required}"
# shellcheck source=test/lib/assert.sh
source "${REPO_ROOT}/test/lib/assert.sh"

check "pixi stub pre-installed by setup" command -v pixi

fail_check "if_exists=fail with pre-installed pixi exits non-zero" \
  bash "${REPO_ROOT}/src/install-pixi/install.bash" \
  --if_exists fail

reportResults
