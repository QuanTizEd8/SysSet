#!/usr/bin/env bash
# macos/get_install_os_pkg.sh — Verify get.sh downloads and installs
# install-os-pkg on macOS using a local HTTP file server.
#
# install-os-pkg is chosen because it is macOS-compatible (uses brew).
# The macOS runner has brew pre-installed; 'tree' will be installed via brew.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/dist/lib/assert.sh
. "${REPO_ROOT}/test/dist/lib/assert.sh"

bash "${REPO_ROOT}/build-artifacts.sh" "v0.1.0-test-macos"

_PORT=18541
trap 'stop_file_server' EXIT
start_file_server "${REPO_ROOT}/dist" "$_PORT"
export SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/"

# install-os-pkg requires root (ospkg::install calls package manager as root).
check "get.sh installs install-os-pkg on macOS (brew installs tree)" \
  sudo -E bash "${REPO_ROOT}/dist/get.sh" install-os-pkg \
  --manifest "tree"

check "tree binary installed by install-os-pkg" \
  command -v tree

reportResults
