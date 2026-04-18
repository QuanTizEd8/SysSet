#!/usr/bin/env bash
# sysset/canonical_order.sh — Verify that sysset.sh enforces canonical install
# order regardless of the order features appear in the manifest.
#
# Strategy: list features in reverse canonical order in the manifest
# (install-pixi first, install-os-pkg second), then confirm execution log
# shows install-os-pkg was processed before install-pixi.
#
# Requires: root (sysset.sh calls os__require_root).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

DIST="${REPO_ROOT}/dist"

_bundle_dir="$(mktemp -d)"
_logfile="$(mktemp)"
trap 'rm -rf "$_bundle_dir" "$_logfile"' EXIT

tar -xzf "${DIST}/sysset-all.tar.gz" -C "$_bundle_dir"

# Manifest lists install-pixi BEFORE install-os-pkg (reverse canonical order).
# Use a tmpdir so we can control the .json extension (BusyBox mktemp lacks --suffix).
_manifest_dir="$(mktemp -d)"
_manifest="${_manifest_dir}/manifest.json"
cat > "$_manifest" << EOF
{
  "features": [
    { "id": "install-pixi", "options": { "version": "0.66.0" } },
    { "id": "install-os-pkg", "options": { "manifest": "${REPO_ROOT}/test/dist/fixtures/ospkg-tree.yaml" } }
  ]
}
EOF
trap 'rm -rf "$_bundle_dir" "$_logfile" "$_manifest_dir"' EXIT

check "sysset.sh completes with canonical-order manifest" \
  bash "${_bundle_dir}/scripts/sysset.sh" "$_manifest" --logfile "$_logfile"

# In the log, install-os-pkg should appear before install-pixi.
check "install-os-pkg ran before install-pixi (canonical order enforced)" \
  bash -c '
    log="'"$_logfile"'"
    line_ospkg=$(grep -n "\[install-os-pkg\]" "$log" | head -1 | cut -d: -f1)
    line_pixi=$(grep -n "\[install-pixi\]" "$log" | head -1 | cut -d: -f1)
    [[ -n "$line_ospkg" && -n "$line_pixi" && "$line_ospkg" -lt "$line_pixi" ]]
  '

reportResults
