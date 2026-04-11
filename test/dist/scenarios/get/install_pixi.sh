#!/usr/bin/env bash
# get/install_pixi.sh — Verify that get.sh can download and install install-pixi
# using a local HTTP file server as the release download origin.
#
# What this tests:
#   • SYSSET_BASE_URL override directs downloads to the local server.
#   • get.sh extracts the tarball and runs the bootstrap correctly.
#   • The installed binary (pixi) is present afterwards.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/dist/lib/assert.sh
. "${REPO_ROOT}/test/dist/lib/assert.sh"

# ── Pre-build dist/ artifacts ─────────────────────────────────────────────────
echo "ℹ️  Building dist/ artifacts ..." >&2
bash "${REPO_ROOT}/build-artifacts.sh" "v0.1.0-test"

# ── Start local file server on an ephemeral port ──────────────────────────────
# python3 -m http.server does not support port 0 on all platforms, so pick a
# fixed high port that is unlikely to be in use.
_PORT=18531
trap 'stop_file_server' EXIT
start_file_server "${REPO_ROOT}/dist" "$_PORT"
export SYSSET_BASE_URL="http://127.0.0.1:${_PORT}/"

# ── Run get.sh ────────────────────────────────────────────────────────────────
# install-pixi requires root (ospkg::require_root); installs pixi to /usr/local/bin.
check "get.sh installs install-pixi successfully" \
  sudo -E bash "${REPO_ROOT}/dist/get.sh" install-pixi

check "pixi binary present in PATH after install" \
  command -v pixi

check "pixi --version succeeds" \
  pixi --version

reportResults
