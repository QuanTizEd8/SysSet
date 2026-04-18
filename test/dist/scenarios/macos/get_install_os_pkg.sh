#!/usr/bin/env bash
# macos/get_install_os_pkg.sh — Verify get.sh downloads and installs a feature
# on macOS using a local HTTP file server.
#
# setup-shim is used because it requires no package manager (no ospkg__run
# call), works on macOS as root, and produces verifiable shim artifacts.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

_PORT=18541
trap 'stop_file_server' EXIT
start_file_server "${REPO_ROOT}/dist" "$_PORT"
export SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/"

check "get.sh installs setup-shim on macOS" \
  sudo env PATH="$PATH" SYSSET_BASE_URL="$SYSSET_BASE_URL" bash "${REPO_ROOT}/dist/get.sh" setup-shim

check "code shim installed by setup-shim" \
  test -f /usr/local/share/setup-shim/bin/code

reportResults
