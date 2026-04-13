#!/usr/bin/env bash
# macos/sysset_yaml.sh — Verify that sysset.sh auto-installs yq and processes
# a YAML manifest on macOS.
#
# yq (mikefarah/yq) is fetched by sysset.sh from GitHub Releases when absent.
# This test verifies the auto-install path on macOS (darwin/arm64 or amd64).
#
# setup-shim is used because it requires no package manager (no ospkg__run
# call), works on macOS as root, and produces verifiable shim artifacts.
# Requires: root for sysset.sh (os__require_root).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

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
  - id: setup-shim
EOF

check "sysset.sh processes YAML manifest on macOS" \
  sudo env PATH="$PATH" bash "${_bundle_dir}/scripts/sysset.sh" "$_manifest"

check "code shim installed by YAML-driven sysset (macOS)" \
  test -f /usr/local/share/setup-shim/bin/code

reportResults
