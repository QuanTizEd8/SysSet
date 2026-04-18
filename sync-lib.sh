#!/usr/bin/env bash
# sync-lib.sh — Assembles each feature's src/ directory from features/ + lib/ + bootstrap.sh:
#   - features/*/metadata.yaml → src/*/devcontainer-feature.json (via scripts/sync-metadata.py)
#   - features/*/metadata.yaml → src/*/dependencies/*.yaml (via scripts/sync-deps.py)
#   - features/*/install.bash  → src/*/install.bash (header prepended via scripts/sync-argparse.py)
#   - lib/                     → src/*/_lib/
#   - bootstrap.sh             → src/*/install.sh
#   - features/*/files/        → src/*/files/ (copied, not symlinked)
#
# Usage:
#   bash sync-lib.sh           # sync all features
#   bash sync-lib.sh --check   # verify copies are up to date
#                              # exits non-zero and reports stale features
#
# Features are auto-discovered from features/*/metadata.yaml — never hard-coded.
set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_LIB_DIR="${_SCRIPT_DIR}/lib"
_FEATURES_DIR="${_SCRIPT_DIR}/features"
_SRC_DIR="${_SCRIPT_DIR}/src"
_BOOTSTRAP="${_SCRIPT_DIR}/bootstrap.sh"

_check_mode=false
[[ "${1-}" == "--check" ]] && _check_mode=true

# ---------------------------------------------------------------------------
# Resolve a Python interpreter that has PyYAML available.
# ---------------------------------------------------------------------------
_python=""
for _candidate in python3 python; do
  if command -v "$_candidate" &> /dev/null &&
    "$_candidate" -c "import yaml" &> /dev/null 2>&1; then
    _python="$_candidate"
    break
  fi
done
if [[ -z "$_python" ]]; then
  echo "ERROR: PyYAML is required.  Install with: pip install pyyaml" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 1: Generate (or check) dependencies/*.yaml from metadata.yaml.
# ---------------------------------------------------------------------------
if [[ "$_check_mode" == true ]]; then
  "$_python" "${_SCRIPT_DIR}/scripts/sync-deps.py" --check
else
  "$_python" "${_SCRIPT_DIR}/scripts/sync-deps.py"
fi

# ---------------------------------------------------------------------------
# Step 3: Generate (or check) devcontainer-feature.json from metadata.yaml.
# ---------------------------------------------------------------------------
if [[ "$_check_mode" == true ]]; then
  "$_python" "${_SCRIPT_DIR}/scripts/sync-metadata.py" --check
else
  "$_python" "${_SCRIPT_DIR}/scripts/sync-metadata.py"
fi

# ---------------------------------------------------------------------------
# Step 4: Generate (or check) argparse blocks in each feature's install.bash.
# ---------------------------------------------------------------------------
if [[ "$_check_mode" == true ]]; then
  "$_python" "${_SCRIPT_DIR}/scripts/sync-argparse.py" --check
else
  "$_python" "${_SCRIPT_DIR}/scripts/sync-argparse.py"
fi

# ---------------------------------------------------------------------------
# Step 5: Auto-discover feature directories (those with a metadata.yaml in features/).
# ---------------------------------------------------------------------------
_feature_dirs=()
while IFS= read -r _meta; do
  _feature_dirs+=("$(dirname "$_meta")")
done < <(find "$_FEATURES_DIR" -maxdepth 2 -name "metadata.yaml")

if [[ ${#_feature_dirs[@]} -eq 0 ]]; then
  echo "⛔ No feature directories found in '${_FEATURES_DIR}'." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Sync or check each feature.
# ---------------------------------------------------------------------------
_any_stale=false

for _feature_dir in "${_feature_dirs[@]}"; do
  _name="$(basename "$_feature_dir")"
  _src_dir="${_SRC_DIR}/${_name}"
  _dest="${_src_dir}/_lib"
  _bootstrap_dest="${_src_dir}/install.sh"

  if [[ "$_check_mode" == true ]]; then
    if [[ ! -d "$_dest" ]]; then
      echo "⛔ ${_name}: _lib/ is missing" >&2
      _any_stale=true
      continue
    fi
    if diff -rq "$_LIB_DIR" "$_dest" > /dev/null 2>&1; then
      echo "✅ ${_name}: in sync" >&2
    else
      echo "⛔ ${_name}: _lib/ is stale" >&2
      diff -r "$_LIB_DIR" "$_dest" >&2 || true
      _any_stale=true
    fi
    if [[ ! -f "$_bootstrap_dest" ]] || ! diff -q "$_BOOTSTRAP" "$_bootstrap_dest" > /dev/null 2>&1; then
      echo "⛔ ${_name}: install.sh is missing or stale" >&2
      _any_stale=true
    fi
  else
    mkdir -p "$_src_dir"
    rm -rf "$_dest"
    mkdir -p "$_dest"
    cp -r "${_LIB_DIR}/." "${_dest}/"
    cp "$_BOOTSTRAP" "$_bootstrap_dest"
    # Copy files/ if the feature source has one (deployment must be self-contained).
    if [[ -d "${_feature_dir}/files" ]]; then
      rm -rf "${_src_dir}/files"
      cp -r "${_feature_dir}/files" "${_src_dir}/files"
    fi
    echo "✅ ${_name}: synced" >&2
  fi
done

if [[ "$_check_mode" == true ]]; then
  if [[ "$_any_stale" == true ]]; then
    echo "" >&2
    echo "⛔ Stale _lib/ copies detected. Run: bash sync-lib.sh" >&2
    echo "   (The pre-commit hook runs this automatically when lib/ files are staged.)" >&2
    exit 1
  fi
  echo "✅ All features in sync." >&2
fi
exit 0
