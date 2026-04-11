#!/usr/bin/env bash
# macos/sysset_json.sh — Verify that sysset.sh processes a JSON manifest and
# installs features on macOS from co-located tarballs in the all-bundle.
#
# setup-shim is used because it requires no package manager (no ospkg::run
# call), works on macOS as root, and produces verifiable shim artifacts.
# Requires: root for sysset.sh (os::require_root).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/dist/lib/assert.sh
. "${REPO_ROOT}/test/dist/lib/assert.sh"

DIST="${REPO_ROOT}/dist"

bash "${REPO_ROOT}/build-artifacts.sh" "v0.1.0-test-macos"

_bundle_dir="$(mktemp -d)"
# Use a tmpdir for the manifest so we can control the .json extension
# (BSD mktemp on macOS does not support --suffix).
_manifest_dir="$(mktemp -d)"
_manifest="${_manifest_dir}/manifest.json"
trap 'rm -rf "$_bundle_dir" "$_manifest_dir"' EXIT

tar -xzf "${DIST}/sysset-all.tar.gz" -C "$_bundle_dir"

cat > "$_manifest" << 'EOF'
{
  "features": [
    { "id": "setup-shim" }
  ]
}
EOF

check "sysset.sh processes JSON manifest on macOS" \
  sudo env PATH="$PATH" bash "${_bundle_dir}/scripts/sysset.sh" "$_manifest"

check "code shim installed by setup-shim (macOS)" \
  test -f /usr/local/share/setup-shim/bin/code

reportResults
