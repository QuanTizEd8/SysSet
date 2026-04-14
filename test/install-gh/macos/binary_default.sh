#!/usr/bin/env bash
# macOS: default install (if_exists=skip).
#
# macOS GHA runners have gh pre-installed (GitHub CLI 2.x).
# Our feature detects the existing installation and exits 0 without making
# any changes, thanks to the if_exists=skip early-exit path that fires
# BEFORE os__require_root. This validates:
#   - the feature script succeeds (exits 0) on macOS without Docker and
#     without root privileges
#   - the early-exit path (VERSION=latest + gh in PATH + if_exists=skip)
#     works correctly end-to-end on macOS
#   - CLI argument parsing works end-to-end
set -e

REPO_ROOT="$1"
# shellcheck source=test/lib/assert.sh
source "${REPO_ROOT}/test/lib/assert.sh"

# --- baseline: gh is in PATH before the feature runs ---
check "gh pre-installed on runner" command -v gh
check "gh --version succeeds" gh --version

# --- run the feature (if_exists=skip default, version=latest default) ---
bash "${REPO_ROOT}/src/install-gh/install.sh" \
  --debug true

# --- gh is still functional after the feature skips ---
check "gh on PATH after feature run" command -v gh
check "gh still returns version string" bash -c 'gh --version | grep -qE "^gh version [0-9]"'

reportResults
