#!/usr/bin/env bash
# get/bad_feature.sh — Verify that get.sh exits non-zero when the requested
# feature tarball is not available at the download URL.
#
# This exercises the error path: HTTP 404 → curl/wget fails → get.sh exits 1.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

bash "${REPO_ROOT}/build-artifacts.sh" "v0.1.0-test"

_PORT=18533
trap 'stop_file_server' EXIT
start_file_server "${REPO_ROOT}/dist" "$_PORT"
export SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/"

# "does-not-exist" is not a real feature — the server returns 404.
fail_check "get.sh exits non-zero for unknown feature" \
  bash "${REPO_ROOT}/dist/get.sh" does-not-exist

reportResults
