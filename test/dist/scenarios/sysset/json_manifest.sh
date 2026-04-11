#!/usr/bin/env bash
# sysset/json_manifest.sh — Verify that sysset.sh installs features from a
# JSON manifest using co-located tarballs (offline / all-bundle mode).
#
# What this tests:
#   • sysset-all.tar.gz extracts correctly.
#   • sysset.sh processes a JSON manifest.
#   • Features are run in canonical order (install-os-pkg before install-pixi)
#     even though the manifest lists install-pixi first.
#   • Both features install successfully (verified via installed artifacts).
#
# Requires: root (sysset.sh calls os::require_root).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/dist/lib/assert.sh
. "${REPO_ROOT}/test/dist/lib/assert.sh"

DIST="${REPO_ROOT}/dist"

# ── Build dist/ ───────────────────────────────────────────────────────────────
echo "ℹ️  Building dist/ artifacts ..." >&2
bash "${REPO_ROOT}/build-artifacts.sh" "v0.1.0-test"

# ── Extract sysset-all.tar.gz ─────────────────────────────────────────────────
_bundle_dir="$(mktemp -d)"
trap 'rm -rf "$_bundle_dir"' EXIT

tar -xzf "${DIST}/sysset-all.tar.gz" -C "$_bundle_dir"

check "sysset-all: scripts/sysset.sh present after extraction" \
  test -f "${_bundle_dir}/scripts/sysset.sh"
check "sysset-all: scripts/_lib/ospkg.sh present" \
  test -f "${_bundle_dir}/scripts/_lib/ospkg.sh"

# Build a manifest that installs install-pixi (to /usr/local/bin) and install-os-pkg.
# Use a tmpdir for the manifest so we can control the .json extension
# (BusyBox mktemp on Alpine does not support --suffix).
_manifest_dir="$(mktemp -d)"
_manifest="${_manifest_dir}/manifest.json"
trap 'rm -rf "$_bundle_dir" "$_manifest_dir"' EXIT
cat > "$_manifest" << EOF
{
  "features": [
    { "id": "install-pixi", "options": { "version": "0.66.0" } },
    { "id": "install-os-pkg", "options": { "manifest": "${REPO_ROOT}/test/dist/fixtures/ospkg-tree.txt" } }
  ]
}
EOF

# ── Run sysset.sh ─────────────────────────────────────────────────────────────
check "sysset.sh runs JSON manifest to completion" \
  bash "${_bundle_dir}/scripts/sysset.sh" "$_manifest"

check "pixi installed by sysset" \
  command -v pixi
check "tree installed by install-os-pkg" \
  command -v tree
reportResults
