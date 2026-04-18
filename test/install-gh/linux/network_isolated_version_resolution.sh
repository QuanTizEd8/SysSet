#!/usr/bin/env bash
# Verify that gh installation fails when the network is blocked (version
# resolution requires the GitHub Releases API).
# The base image (built by run-linux.sh) pre-installs feature dependencies.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required}"
# shellcheck source=test/lib/assert.sh
source "${REPO_ROOT}/test/lib/assert.sh"

fail_check "network-isolated: version resolution fails" \
  bash "${REPO_ROOT}/src/install-gh/install.bash"

reportResults
