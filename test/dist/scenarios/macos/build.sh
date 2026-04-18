#!/usr/bin/env bash
# macos/build.sh — Verify that build-artifacts.sh produces correct artifacts on macOS.
#
# Checks the same layout as build/default.sh but run natively on a macOS runner.
# macOS ships BSD tar (gtar may not be present); test uses system tar.
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"
DIST="${REPO_ROOT}/dist"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

check "dist/get.sh exists" test -f "${DIST}/get.sh"
check "dist/sysset-all.tar.gz exists" test -f "${DIST}/sysset-all.tar.gz"
check "dist/scripts/ cleaned up after build" test ! -d "${DIST}/scripts"

check "dist/get.sh no placeholder" \
  bash -c "! grep -q '@@RELEASE_TAG@@' '${DIST}/get.sh'"
[[ -n "${SYSSET_BUILD_VERSION:-}" ]] && check "dist/get.sh tag stamped" \
  bash -c "grep -q '${SYSSET_BUILD_VERSION}' '${DIST}/get.sh'"

# spot-check a few features
for _feat in install-pixi install-os-pkg setup-user; do
  check "sysset-${_feat}.tar.gz exists" test -f "${DIST}/sysset-${_feat}.tar.gz"
  check "sysset-${_feat}: contains install.bash" \
    bash -c "tar -tzf '${DIST}/sysset-${_feat}.tar.gz' | grep -q 'install\.bash'"
  check "sysset-${_feat}: contains _lib/" \
    bash -c "tar -tzf '${DIST}/sysset-${_feat}.tar.gz' | grep -q '_lib/'"
done

check "sysset-all: contains scripts/sysset.sh" \
  bash -c "tar -tzf '${DIST}/sysset-all.tar.gz' | grep -q 'scripts/sysset\.sh'"

reportResults
