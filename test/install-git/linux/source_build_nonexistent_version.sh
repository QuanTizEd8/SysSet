#!/usr/bin/env bash
# Verify that requesting a nonexistent version (0.0.0) fails the source build.
#
# ospkg__run installs build deps (including curl) before the download attempt,
# so no SETUP_CMD is needed — the feature handles its own dep installation.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required}"
# shellcheck source=test/lib/assert.sh
source "${REPO_ROOT}/test/lib/assert.sh"

fail_check "source build: nonexistent version 0.0.0 exits non-zero" \
  bash "${REPO_ROOT}/src/install-git/install.bash" \
  --method source \
  --version 0.0.0

reportResults
