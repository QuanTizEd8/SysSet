#!/usr/bin/env bash
# sysset/fail_partial.sh — Verify that sysset.sh reports failure when one
# feature fails, but continues to attempt the remaining features.
#
# Strategy: include a non-existent feature alongside a valid one.
# The valid feature (install-pixi) should still be installed, but sysset.sh
# must exit non-zero because the bogus feature download failed.
#
# Requires: root (sysset.sh calls os__require_root).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/dist/lib/assert.sh
. "${REPO_ROOT}/test/dist/lib/assert.sh"

DIST="${REPO_ROOT}/dist"

bash "${REPO_ROOT}/build-artifacts.sh" "v0.1.0-test"

_bundle_dir="$(mktemp -d)"
# Use a tmpdir so we can control the .json extension (BusyBox mktemp lacks --suffix).
_manifest_dir="$(mktemp -d)"
_manifest="${_manifest_dir}/manifest.json"
trap 'rm -rf "$_bundle_dir" "$_manifest_dir"' EXIT

tar -xzf "${DIST}/sysset-all.tar.gz" -C "$_bundle_dir"

# "does-not-exist" has no tarball; install-pixi is valid.
cat > "$_manifest" << EOF
{
  "features": [
    { "id": "install-pixi", "options": { "version": "0.66.0" } },
    { "id": "does-not-exist",  "options": {} }
  ]
}
EOF

# sysset.sh should exit non-zero overall.
fail_check "sysset.sh exits non-zero when a feature fails" \
  bash "${_bundle_dir}/scripts/sysset.sh" "$_manifest"

# But install-pixi (the valid feature) should still have run.
check "install-pixi still installed despite partial failure" \
  command -v pixi

reportResults
