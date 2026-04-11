#!/usr/bin/env bash
# sysset/override_order.sh — Verify that override_install_order: true causes
# features to run in manifest order, not canonical order.
#
# Strategy: manifest lists install-pixi before install-os-pkg with
# override_install_order: true. The log should show install-pixi first.
#
# Requires: root (sysset.sh calls os::require_root).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/dist/lib/assert.sh
. "${REPO_ROOT}/test/dist/lib/assert.sh"

DIST="${REPO_ROOT}/dist"

bash "${REPO_ROOT}/build-artifacts.sh" "v0.1.0-test"

_bundle_dir="$(mktemp -d)"
_logfile="$(mktemp)"
_manifest="$(mktemp --suffix=.json)"
trap 'rm -rf "$_bundle_dir" "$_logfile"; rm -f "$_manifest"' EXIT

tar -xzf "${DIST}/sysset-all.tar.gz" -C "$_bundle_dir"

cat > "$_manifest" << EOF
{
  "override_install_order": true,
  "features": [
    { "id": "install-pixi", "options": { "version": "0.66.0" } },
    { "id": "install-os-pkg", "options": { "manifest": "${REPO_ROOT}/test/dist/fixtures/ospkg-tree.txt" } }
  ]
}
EOF

check "sysset.sh completes with override_install_order: true" \
  bash "${_bundle_dir}/scripts/sysset.sh" "$_manifest" --logfile "$_logfile"

# install-pixi should appear BEFORE install-os-pkg in the log.
check "install-pixi ran before install-os-pkg (override order respected)" \
  bash -c '
    log="'"$_logfile"'"
    line_pixi=$(grep -n "\[install-pixi\]" "$log" | head -1 | cut -d: -f1)
    line_ospkg=$(grep -n "\[install-os-pkg\]" "$log" | head -1 | cut -d: -f1)
    [[ -n "$line_pixi" && -n "$line_ospkg" && "$line_pixi" -lt "$line_ospkg" ]]
  '

reportResults
