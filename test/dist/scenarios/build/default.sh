#!/usr/bin/env bash
# build/default.sh — Verify that build-artifacts.sh produces a correct dist/ layout.
#
# Checks:
#   1. Per-feature tarballs exist for every feature with an install.bash.
#   2. Each tarball contains: install.sh, install.bash, _lib/.
#   3. sysset-all.tar.gz exists and contains get.sh, scripts/sysset.sh,
#      scripts/_lib/, and all per-feature tarballs.
#   4. dist/get.sh has the tag stamped (no @@RELEASE_TAG@@ placeholder).
#   5. dist/scripts does NOT remain after the build (cleaned up).
set -euo pipefail

REPO_ROOT="${1:?REPO_ROOT required as \$1}"
DIST="${REPO_ROOT}/dist"

# shellcheck source=test/lib/assert.sh
. "${REPO_ROOT}/test/lib/assert.sh"

# ── Helper: list features that have an install.bash ─────────────────────────
_features=()
while IFS= read -r _json; do
  _dir="$(dirname "$_json")"
  _name="$(basename "$_dir")"
  [[ -f "${_dir}/install.bash" ]] && _features+=("$_name")
done < <(find "${REPO_ROOT}/src" -maxdepth 2 -name "devcontainer-feature.json" | sort)

# ── Checks ────────────────────────────────────────────────────────────────────

check "dist/get.sh exists" test -f "${DIST}/get.sh"
check "dist/sysset-all.tar.gz exists" test -f "${DIST}/sysset-all.tar.gz"
check "dist/scripts/ cleaned up after build" test ! -d "${DIST}/scripts"

check "dist/get.sh tag stamped (no placeholder)" \
  bash -c "! grep -q '@@RELEASE_TAG@@' '${DIST}/get.sh'"
[[ -n "${SYSSET_BUILD_VERSION:-}" ]] && check "dist/get.sh stamped with expected tag" \
  bash -c "grep -q '${SYSSET_BUILD_VERSION}' '${DIST}/get.sh'"

for _feat in "${_features[@]}"; do
  _tarball="${DIST}/sysset-${_feat}.tar.gz"
  check "sysset-${_feat}.tar.gz exists" test -f "$_tarball"
  check "sysset-${_feat}: contains install.sh" \
    bash -c "tar -tzf '${_tarball}' | grep -qx '\./install\.sh\|install\.sh'"
  check "sysset-${_feat}: contains install.bash" \
    bash -c "tar -tzf '${_tarball}' | grep -qx '\./install\.bash\|install\.bash'"
  check "sysset-${_feat}: contains _lib/" \
    bash -c "tar -tzf '${_tarball}' | grep -q '_lib/'"
done

# sysset-all.tar.gz contains per-feature tarballs + get.sh + sysset.sh + _lib/
check "sysset-all: contains get.sh" \
  bash -c "tar -tzf '${DIST}/sysset-all.tar.gz' | grep -qx '\./get\.sh\|get\.sh'"
check "sysset-all: contains scripts/sysset.sh" \
  bash -c "tar -tzf '${DIST}/sysset-all.tar.gz' | grep -q 'scripts/sysset\.sh'"
check "sysset-all: contains scripts/_lib/" \
  bash -c "tar -tzf '${DIST}/sysset-all.tar.gz' | grep -q 'scripts/_lib/'"
for _feat in "${_features[@]}"; do
  check "sysset-all: contains sysset-${_feat}.tar.gz" \
    bash -c "tar -tzf '${DIST}/sysset-all.tar.gz' | grep -q 'sysset-${_feat}\.tar\.gz'"
done

check "sysset-all: sysset.sh tag stamped (no placeholder)" \
  bash -c "! tar -xOzf '${DIST}/sysset-all.tar.gz' scripts/sysset.sh | grep -q '@@RELEASE_TAG@@'"

reportResults
