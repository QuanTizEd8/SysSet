#!/usr/bin/env bash
# Verify that a source build fails when the network is blocked (version resolution
# requires network access to query the GitHub Releases API).
# The base image (built by run-linux.sh) pre-installs feature dependencies so
# apt-get is not needed inside the isolated container.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required}"
# shellcheck source=test/lib/assert.sh
source "${REPO_ROOT}/test/lib/assert.sh"

fail_check "source build: network-isolated version resolution fails" \
  bash "${REPO_ROOT}/src/install-git/install.bash" \
  --method source

reportResults
