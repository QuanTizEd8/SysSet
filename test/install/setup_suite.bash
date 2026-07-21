#!/usr/bin/env bash
# Install-framework tests use the same immutable jq/yq cache as ordinary
# library tests. The scenario prepares the binaries before BATS starts; this
# suite hook validates and privately copies them once for the complete run.

# shellcheck source=test/lib/setup_suite.bash
source "${REPO_ROOT:?REPO_ROOT must identify the repository}/test/lib/setup_suite.bash"
