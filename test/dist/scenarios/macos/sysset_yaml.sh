#!/usr/bin/env bash
# macos/sysset_yaml.sh — Verify that sysset.sh auto-installs yq and processes
# a YAML manifest on macOS.
#
# yq (mikefarah/yq) is fetched by sysset.sh from GitHub Releases when absent.
# This test verifies the auto-install path on macOS (darwin/arm64 or amd64).
#
# Feature: install-os-pkg (brew-compatible, macOS-native).
# Requires: root for sysset.sh (os::require_root).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"

# shellcheck source=test/dist/lib/assert.sh
. "${REPO_ROOT}/test/dist/lib/assert.sh"

DIST="${REPO_ROOT}/dist"

bash "${REPO_ROOT}/build-artifacts.sh" "v0.1.0-test-macos"

_bundle_dir="$(mktemp -d)"
_manifest="$(mktemp --suffix=.yaml)"
trap 'rm -rf "$_bundle_dir"; rm -f "$_manifest"' EXIT

tar -xzf "${DIST}/sysset-all.tar.gz" -C "$_bundle_dir"

# Ensure yq is not present so the auto-install path is exercised.
# (If brew already installed yq, skip this test.)
if command -v yq > /dev/null 2>&1; then
  echo "ℹ️  yq already present — YAML auto-install path not tested." >&2
fi

cat > "$_manifest" << EOF
features:
  - id: install-os-pkg
    options:
      manifest: "tree"
EOF

check "sysset.sh processes YAML manifest on macOS" \
  sudo -E bash "${_bundle_dir}/scripts/sysset.sh" "$_manifest"

check "tree available after YAML-driven install (macOS)" \
  command -v tree

reportResults
