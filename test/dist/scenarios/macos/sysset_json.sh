#!/usr/bin/env bash
# macos/sysset_json.sh — Verify that sysset.sh processes a JSON manifest and
# installs features on macOS from co-located tarballs in the all-bundle.
#
# Features: install-os-pkg (brew-compatible, macOS-native).
# Requires: root for sysset.sh (os::require_root).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/dist/lib/assert.sh
. "${REPO_ROOT}/test/dist/lib/assert.sh"

DIST="${REPO_ROOT}/dist"

bash "${REPO_ROOT}/build-artifacts.sh" "v0.1.0-test-macos"

_bundle_dir="$(mktemp -d)"
_manifest="$(mktemp --suffix=.json)"
trap 'rm -rf "$_bundle_dir"; rm -f "$_manifest"' EXIT

tar -xzf "${DIST}/sysset-all.tar.gz" -C "$_bundle_dir"

cat > "$_manifest" << EOF
{
  "features": [
    { "id": "install-os-pkg", "options": { "manifest": "${REPO_ROOT}/test/dist/fixtures/ospkg-tree.txt" } }
  ]
}
EOF

check "sysset.sh processes JSON manifest on macOS" \
  sudo env PATH="$PATH" bash "${_bundle_dir}/scripts/sysset.sh" "$_manifest"

check "tree available after install-os-pkg (macOS)" \
  command -v tree

reportResults
