#!/usr/bin/env bash
# Verify that a version string with an invalid suffix (e.g. "1.2beta") is rejected
# by the semver validator — only X.Y or X.Y.Z with digits are accepted.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required}"
# shellcheck source=test/lib/assert.sh
source "${REPO_ROOT}/test/lib/assert.sh"

fail_check "version with invalid suffix '1.2beta' exits non-zero" \
  bash "${REPO_ROOT}/src/install-pixi/install.bash" \
  --version 1.2beta

reportResults
