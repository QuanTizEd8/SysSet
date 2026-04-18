#!/usr/bin/env bash
# build-artifacts.sh — Assemble standalone distribution artifacts into dist/.
#
# Usage:
#   bash build-artifacts.sh [<tag>]
#
#   <tag>   Release tag to stamp into get.sh and sysset.sh
#           (default: "dev" — for local test runs)
#
# Outputs (all under dist/):
#   get.sh                        Version-stamped single-feature downloader
#   sysset-<feature>.tar.gz       One tarball per feature
#   sysset-all.tar.gz             All tarballs + get.sh + scripts/sysset.sh + scripts/_lib/
#
# Tarball layout (per feature):
#   install.sh        POSIX sh bootstrap (handles bash>=4 on any platform)
#   install.bash      Real bash>=4 installer
#   _lib/             Full lib/ copy
#   dependencies/     Optional — only when src/<feature>/dependencies/ exists
#   files/            Optional — only when src/<feature>/files/ exists
set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_TAG="${1:-dev}"

echo "ℹ️  Building artifacts for tag: '${_TAG}'" >&2

# ── Pre-flight: require src/ to be already populated by sync-lib.sh ─────────
# build-artifacts.sh is a consumer of sync output — it does not call sync
# itself to stay usable in environments without Python+PyYAML (e.g. containers).
# Run 'bash sync-lib.sh' (or 'make sync') before invoking this script.
_check_feature=$(find "${_SCRIPT_DIR}/src" -maxdepth 2 -name 'install.bash' 2> /dev/null | head -1)
if [[ -z "$_check_feature" ]]; then
  echo "⛔ src/ is not populated. Run 'bash sync-lib.sh' first." >&2
  exit 1
fi

# ── Step 1: Clean and create dist/ ──────────────────────────────────────────
rm -rf "${_SCRIPT_DIR}/dist"
mkdir -p "${_SCRIPT_DIR}/dist"

# ── Step 2: Auto-discover features from features/ (assembled artifacts are in src/) ─
_feature_dirs=()
while IFS= read -r _bash; do
  _dir="$(dirname "$_bash")"
  _name="$(basename "$_dir")"
  _src_dir="${_SCRIPT_DIR}/src/${_name}"
  [[ -f "${_src_dir}/install.bash" ]] && _feature_dirs+=("$_src_dir")
done < <(find "${_SCRIPT_DIR}/features" -maxdepth 2 -name "install.bash" | sort)

if [[ ${#_feature_dirs[@]} -eq 0 ]]; then
  echo "⛔ No features with an install.bash found." >&2
  exit 1
fi

echo "ℹ️  Found ${#_feature_dirs[@]} features." >&2

# ── Step 3: Build per-feature tarballs ──────────────────────────────────────────
for _feature_dir in "${_feature_dirs[@]}"; do
  _name="$(basename "$_feature_dir")"
  _staging="${_SCRIPT_DIR}/dist/tmp/${_name}"
  _tarball="${_SCRIPT_DIR}/dist/sysset-${_name}.tar.gz"

  mkdir -p "$_staging"

  # Always include: bootstrap and real installer (with _lib/)
  cp "${_feature_dir}/install.sh" "${_staging}/install.sh"
  cp "${_feature_dir}/install.bash" "${_staging}/install.bash"
  cp -r "${_feature_dir}/_lib/" "${_staging}/_lib/"

  # Optional: dependencies/
  if [[ -d "${_feature_dir}/dependencies" ]]; then
    cp -r "${_feature_dir}/dependencies/" "${_staging}/dependencies/"
  fi

  # Optional: files/
  if [[ -d "${_feature_dir}/files" ]]; then
    cp -r "${_feature_dir}/files/" "${_staging}/files/"
  fi

  tar -czf "$_tarball" -C "$_staging" .
  rm -rf "$_staging"
  echo "✅ ${_name}: built sysset-${_name}.tar.gz" >&2
done

rm -rf "${_SCRIPT_DIR}/dist/tmp"

# ── Step 4: Stamp get.sh ──────────────────────────────────────────────────────
sed "s|@@RELEASE_TAG@@|${_TAG}|g" "${_SCRIPT_DIR}/get.sh" \
  > "${_SCRIPT_DIR}/dist/get.sh"
chmod +x "${_SCRIPT_DIR}/dist/get.sh"
echo "✅ Stamped dist/get.sh with tag '${_TAG}'" >&2

# ── Step 5: Stamp sysset.sh and copy _lib/ for the all-bundle ──────────────────
mkdir -p "${_SCRIPT_DIR}/dist/scripts"
sed "s|@@RELEASE_TAG@@|${_TAG}|g" "${_SCRIPT_DIR}/sysset.sh" \
  > "${_SCRIPT_DIR}/dist/scripts/sysset.sh"
chmod +x "${_SCRIPT_DIR}/dist/scripts/sysset.sh"
cp -r "${_SCRIPT_DIR}/lib/." "${_SCRIPT_DIR}/dist/scripts/_lib/"
echo "✅ Stamped dist/scripts/sysset.sh with tag '${_TAG}'" >&2

# ── Step 6: Build all-bundle ──────────────────────────────────────────────────────
# Collect individual feature tarballs (must exist before sysset-all.tar.gz is created)
_feature_tarballs=()
while IFS= read -r _t; do
  _feature_tarballs+=("$(basename "$_t")")
done < <(find "${_SCRIPT_DIR}/dist" -maxdepth 1 -name "sysset-*.tar.gz" | sort)

(
  cd "${_SCRIPT_DIR}/dist"
  tar -czf sysset-all.tar.gz \
    get.sh \
    scripts/ \
    "${_feature_tarballs[@]}"
)
echo "✅ Built dist/sysset-all.tar.gz" >&2

# ── Step 7: Clean up intermediate scripts/ dir from dist/ root ─────────────────
rm -rf "${_SCRIPT_DIR}/dist/scripts"

echo "" >&2
echo "✅ Build complete. Artifacts in dist/:" >&2
ls -lh "${_SCRIPT_DIR}/dist/" >&2
