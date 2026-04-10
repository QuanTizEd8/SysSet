#!/usr/bin/env bash
# sync-lib.sh — Distributes shared files into each feature directory:
#   - .devcontainer/lib/          → each feature's scripts/_lib/
#   - .devcontainer/bootstrap.sh  → each feature's install.sh
#
# Usage:
#   bash .devcontainer/sync-lib.sh           # sync all features
#   bash .devcontainer/sync-lib.sh --check   # verify copies are up to date
#                                            # exits non-zero and reports stale features
#
# Features are auto-discovered — never hard-coded. Any feature directory that
# contains a scripts/ subdirectory receives a scripts/_lib/ copy.
set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_LIB_DIR="${_SCRIPT_DIR}/lib"
_SRC_DIR="${_SCRIPT_DIR}/src"
_BOOTSTRAP="${_SCRIPT_DIR}/bootstrap.sh"

_check_mode=false
[[ "${1-}" == "--check" ]] && _check_mode=true

# ---------------------------------------------------------------------------
# Auto-discover feature directories that have a scripts/ subdirectory.
# ---------------------------------------------------------------------------
_feature_dirs=()
while IFS= read -r _json; do
  _dir="$(dirname "$_json")"
  [[ -d "${_dir}/scripts" ]] && _feature_dirs+=("$_dir")
done < <(find "$_SRC_DIR" -maxdepth 2 -name "devcontainer-feature.json")

if [[ ${#_feature_dirs[@]} -eq 0 ]]; then
  echo "⛔ No features with a scripts/ subdirectory found in '${_SRC_DIR}'." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Sync or check each feature.
# ---------------------------------------------------------------------------
_any_stale=false

for _feature_dir in "${_feature_dirs[@]}"; do
  _name="$(basename "$_feature_dir")"
  _dest="${_feature_dir}/scripts/_lib"
  _bootstrap_dest="${_feature_dir}/install.sh"

  if [[ "$_check_mode" == true ]]; then
    if [[ ! -d "$_dest" ]]; then
      echo "⛔ ${_name}: scripts/_lib/ is missing" >&2
      _any_stale=true
      continue
    fi
    if diff -rq "$_LIB_DIR" "$_dest" > /dev/null 2>&1; then
      echo "✅ ${_name}: in sync" >&2
    else
      echo "⛔ ${_name}: scripts/_lib/ is stale" >&2
      diff -r "$_LIB_DIR" "$_dest" >&2 || true
      _any_stale=true
    fi
    if [[ ! -f "$_bootstrap_dest" ]] || ! diff -q "$_BOOTSTRAP" "$_bootstrap_dest" > /dev/null 2>&1; then
      echo "⛔ ${_name}: install.sh is missing or stale" >&2
      _any_stale=true
    fi
  else
    rm -rf "$_dest"
    mkdir -p "$_dest"
    cp -r "${_LIB_DIR}/." "${_dest}/"
    cp "$_BOOTSTRAP" "$_bootstrap_dest"
    echo "✅ ${_name}: synced" >&2
  fi
done

if [[ "$_check_mode" == true ]]; then
  if [[ "$_any_stale" == true ]]; then
    echo "" >&2
    echo "⛔ Stale _lib/ copies detected. Run: bash .devcontainer/sync-lib.sh" >&2
    echo "   (The pre-commit hook runs this automatically when lib/ files are staged.)" >&2
    exit 1
  fi
  echo "✅ All features in sync." >&2
fi
exit 0
