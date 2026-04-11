#!/usr/bin/env bash
# macos/sysset_json.sh — Verify that sysset.sh processes a JSON manifest and
# installs features on macOS from co-located tarballs in the all-bundle.
#
# install-pixi is used because it is macOS-compatible and does not depend on
# brew (which cannot run as root).  install-os-pkg is Linux-only.
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
    { "id": "install-pixi" }
  ]
}
EOF

check "sysset.sh processes JSON manifest on macOS" \
  sudo env PATH="$PATH" bash "${_bundle_dir}/scripts/sysset.sh" "$_manifest"

check "pixi installed by install-pixi (macOS)" \
  command -v pixi

reportResults
