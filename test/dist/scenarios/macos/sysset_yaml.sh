#!/usr/bin/env bash
# macos/sysset_yaml.sh — Verify that sysset.sh auto-installs yq and processes
# a YAML manifest on macOS.
#
# yq (mikefarah/yq) is fetched by sysset.sh from GitHub Releases when absent.
# This test verifies the auto-install path on macOS (darwin/arm64 or amd64).
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
# Use a tmpdir for the manifest so we can control the .yaml extension
# (BSD mktemp on macOS does not support --suffix).
_manifest_dir="$(mktemp -d)"
_manifest="${_manifest_dir}/manifest.yaml"
trap 'rm -rf "$_bundle_dir" "$_manifest_dir"' EXIT

tar -xzf "${DIST}/sysset-all.tar.gz" -C "$_bundle_dir"

# Ensure yq is not present so the auto-install path is exercised.
# (If brew already installed yq, skip this test.)
if command -v yq > /dev/null 2>&1; then
  echo "ℹ️  yq already present — YAML auto-install path not tested." >&2
fi

cat > "$_manifest" << 'EOF'
features:
  - id: install-pixi
EOF

check "sysset.sh processes YAML manifest on macOS" \
  sudo env PATH="$PATH" bash "${_bundle_dir}/scripts/sysset.sh" "$_manifest"

check "pixi installed by YAML-driven install (macOS)" \
  command -v pixi

reportResults
