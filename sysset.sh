#!/usr/bin/env bash
# sysset.sh — Install multiple sysset features from a JSON or YAML manifest.
#
# Must be run from its installed location (scripts/sysset.sh inside the
# sysset-all.tar.gz bundle) so that _lib/ is available at the same level.
#
# Usage:
#   sysset.sh <manifest.json|.yaml> [--tag <tag>] [--logfile <path>] [--debug]
#
# This script is version-stamped at release build time (@@RELEASE_TAG@@ is
# replaced with the actual release tag by build-artifacts.sh). Running it
# without --tag always installs from the same release it was bundled with.
#
# Manifest format (JSON):
#   {
#     "tag": "v1.2",                  // optional — overrides stamped tag
#     "override_install_order": false, // optional — default false
#     "features": [
#       { "id": "install-pixi",  "options": { "version": "0.66.0" } },
#       { "id": "install-shell", "options": { "shell": "zsh" } }
#     ]
#   }
#
# When override_install_order is false (default), features are installed in
# the canonical order regardless of their order in the manifest. Unknown
# feature IDs are appended after all known ones, in manifest order.
set -euo pipefail

_SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
SYSSET_RELEASE_TAG="@@RELEASE_TAG@@"
SYSSET_REPO="quantized8/sysset"

# ── Library sourcing ──────────────────────────────────────────────────────────
# shellcheck source=lib/ospkg.sh
. "$_SELF_DIR/_lib/ospkg.sh" # also sources os.sh and net.sh
# shellcheck source=lib/logging.sh
. "$_SELF_DIR/_lib/logging.sh"
# shellcheck source=lib/github.sh
. "$_SELF_DIR/_lib/github.sh"

logging::setup
trap 'logging::cleanup' EXIT

echo "↪️  Script entry: sysset manifest installer" >&2

# ── Canonical install order ───────────────────────────────────────────────────
_CANONICAL_ORDER=(
  setup-user
  install-homebrew
  install-os-pkg
  install-shell
  install-miniforge
  install-conda-env
  install-pixi
  install-podman
  install-fonts
  setup-shim
)

# ── Usage ─────────────────────────────────────────────────────────────────────
__usage__() {
  cat >&2 << EOF
Usage: sysset.sh <manifest> [OPTIONS]

  <manifest>       Path to a .json or .yaml installation manifest

Options:
  --tag <tag>      Override the release tag for all feature downloads
                   (default: ${SYSSET_RELEASE_TAG})
  --logfile <path> Append combined log output to this file
  --debug          Enable bash -x trace output
  --help, -h       Show this help

Manifest format (JSON):
  {
    "tag": "v1.2",
    "override_install_order": false,
    "features": [
      { "id": "install-pixi",  "options": { "version": "0.66.0" } },
      { "id": "install-shell", "options": { "shell": "zsh" } }
    ]
  }

Canonical install order (used when override_install_order is false):
$(
    for _f in "${_CANONICAL_ORDER[@]}"; do
      echo "  $_f"
    done
  )
  <unknown features in manifest order>
EOF
  exit "${1:-0}"
}

# ── Argument parsing (CLI-only) ───────────────────────────────────────────────
_MANIFEST=""
_TAG="$SYSSET_RELEASE_TAG"
DEBUG=false
LOGFILE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --tag)
      shift
      if [[ $# -eq 0 ]]; then
        echo "⛔ --tag requires a value." >&2
        exit 1
      fi
      _TAG="$1"
      echo "📩 Read argument 'tag': '${_TAG}'" >&2
      shift
      ;;
    --logfile)
      shift
      if [[ $# -eq 0 ]]; then
        echo "⛔ --logfile requires a value." >&2
        exit 1
      fi
      LOGFILE="$1"
      echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2
      shift
      ;;
    --debug)
      DEBUG=true
      echo "📩 Read argument 'debug': 'true'" >&2
      shift
      ;;
    --help | -h) __usage__ ;;
    --*)
      echo "⛔ Unknown option: '${1}'" >&2
      exit 1
      ;;
    *)
      if [[ -z "$_MANIFEST" ]]; then
        _MANIFEST="$1"
        shift
      else
        echo "⛔ Unexpected argument: '${1}'" >&2
        exit 1
      fi
      ;;
  esac
done

[[ "$DEBUG" == true ]] && set -x

# ── Validate inputs ───────────────────────────────────────────────────────────
if [[ -z "$_MANIFEST" ]]; then
  echo "⛔ No manifest file specified." >&2
  __usage__ 1
fi
if [[ ! -f "$_MANIFEST" ]]; then
  echo "⛔ Manifest not found: '${_MANIFEST}'" >&2
  exit 1
fi

# ── Preconditions ─────────────────────────────────────────────────────────────
os::require_root

# ── Detect manifest format ────────────────────────────────────────────────────
_ext="${_MANIFEST##*.}"
_is_yaml=false
case "$_ext" in
  yaml | yml) _is_yaml=true ;;
  json) _is_yaml=false ;;
  *)
    echo "⛔ Unrecognised manifest extension '.${_ext}'. Use .json, .yaml, or .yml." >&2
    exit 1
    ;;
esac

# ── Auto-install parser dependencies ─────────────────────────────────────────

# jq — always needed (JSON baseline; yq is built on top of it for YAML)
if ! command -v jq > /dev/null 2>&1; then
  echo "ℹ️  jq not found — installing via package manager." >&2
  ospkg::install jq
fi

# yq (mikefarah/yq) — only needed for YAML manifests.
# Fetched directly from GitHub Releases (distro-packaged yq is a different,
# incompatible binary).
_install_yq() {
  local _os _arch _url
  _os="$(os::kernel | tr '[:upper:]' '[:lower:]')" # linux | darwin
  _arch="$(os::arch)"
  case "$_arch" in
    x86_64) _arch="amd64" ;;
    aarch64 | arm64) _arch="arm64" ;;
    *)
      echo "⛔ Unsupported architecture for yq: ${_arch}" >&2
      return 1
      ;;
  esac
  _url="$(github::release_asset_urls mikefarah/yq \
    --filter "yq_${_os}_${_arch}$" | head -1)"
  if [[ -z "$_url" ]]; then
    echo "⛔ Could not find yq release asset for ${_os}/${_arch}." >&2
    return 1
  fi
  echo "ℹ️  Downloading yq from: ${_url}" >&2
  net::fetch_url_file "$_url" /usr/local/bin/yq
  chmod +rx /usr/local/bin/yq
  echo "✅ yq installed to /usr/local/bin/yq" >&2
  return 0
}

if [[ "$_is_yaml" == true ]] && ! command -v yq > /dev/null 2>&1; then
  echo "ℹ️  yq not found — fetching from GitHub Releases." >&2
  _install_yq
fi

# Choose parser: prefer yq (handles both JSON and YAML natively).
if command -v yq > /dev/null 2>&1; then
  _PARSER="yq"
else
  _PARSER="jq"
fi
echo "ℹ️  Using parser: ${_PARSER}" >&2

# ── Parse manifest top-level fields ──────────────────────────────────────────
_override_order="$("$_PARSER" -r '.override_install_order // false' "$_MANIFEST")"
_manifest_tag="$("$_PARSER" -r '.tag // ""' "$_MANIFEST")"
if [[ -n "$_manifest_tag" ]]; then
  _TAG="$_manifest_tag"
  echo "ℹ️  Tag overridden by manifest: '${_TAG}'" >&2
fi

echo "ℹ️  Release tag: '${_TAG}'" >&2
echo "ℹ️  override_install_order: '${_override_order}'" >&2

# Read feature IDs in manifest order.
mapfile -t _manifest_features < <("$_PARSER" -r '.features[].id' "$_MANIFEST")

if [[ ${#_manifest_features[@]} -eq 0 ]]; then
  echo "⛔ No features found in manifest." >&2
  exit 1
fi

echo "ℹ️  Manifest features (${#_manifest_features[@]}): ${_manifest_features[*]}" >&2

# ── Determine execution order ─────────────────────────────────────────────────
_sorted_features=()

_sort_features() {
  local _feat _known _found

  # Pass 1: emit manifest features that appear in the canonical list, in
  # canonical order (so dependencies are always satisfied).
  for _known in "${_CANONICAL_ORDER[@]}"; do
    for _feat in "${_manifest_features[@]}"; do
      if [[ "$_feat" == "$_known" ]]; then
        _sorted_features+=("$_feat")
        break
      fi
    done
  done

  # Pass 2: append manifest features not in the canonical list (unknown
  # features), preserving their manifest order.
  for _feat in "${_manifest_features[@]}"; do
    _found=false
    for _known in "${_CANONICAL_ORDER[@]}"; do
      [[ "$_feat" == "$_known" ]] && {
        _found=true
        break
      }
    done
    [[ "$_found" == false ]] && _sorted_features+=("$_feat")
  done
  return 0
}

if [[ "$_override_order" == "true" ]]; then
  _sorted_features=("${_manifest_features[@]}")
  echo "ℹ️  Using manifest order (override_install_order: true)" >&2
else
  _sort_features
  echo "ℹ️  Using canonical install order" >&2
fi

echo "ℹ️  Execution order: ${_sorted_features[*]}" >&2

# ── Feature runner ────────────────────────────────────────────────────────────
_run_feature() {
  local _feature="$1"
  shift
  local _opts=("$@")

  local _tmpdir
  _tmpdir="$(mktemp -d)"

  # Prefer a co-located feature tarball (offline use / sysset-all.tar.gz bundle).
  # _SELF_DIR is scripts/; the tarballs live one level up alongside get.sh.
  local _local_tarball="${_SELF_DIR}/../sysset-${_feature}.tar.gz"
  if [[ -f "$_local_tarball" ]]; then
    echo "ℹ️  [${_feature}] Using local tarball" >&2
    cp "$_local_tarball" "$_tmpdir/feature.tar.gz"
  else
    local _url="https://github.com/${SYSSET_REPO}/releases/download/${_TAG}/sysset-${_feature}.tar.gz"
    echo "ℹ️  [${_feature}] Downloading @ ${_TAG} ..." >&2
    if ! net::fetch_url_file "$_url" "$_tmpdir/feature.tar.gz"; then
      rm -rf "$_tmpdir"
      echo "⛔ [${_feature}] Failed to download tarball." >&2
      return 1
    fi
  fi

  tar -xzf "$_tmpdir/feature.tar.gz" -C "$_tmpdir"
  local _exit=0

  # The tarball root contains a POSIX sh bootstrap that handles bash>=4
  # and then execs scripts/install.sh "$@".
  sh "$_tmpdir/install.sh" "${_opts[@]+"${_opts[@]}"}" || _exit=$?

  rm -rf "$_tmpdir"
  return "$_exit"
}

# ── Main install loop ─────────────────────────────────────────────────────────
_passed=()
_failed=()

for _feature in "${_sorted_features[@]}"; do
  # Extract options for this feature from the manifest.
  # .value | tostring converts booleans and numbers to strings so they are
  # safely forwarded as shell arguments.
  # SC2016: $feat is a jq variable bound by --arg, not a bash variable — no expansion intended.
  # shellcheck disable=SC2016
  mapfile -t _opts < <(
    "$_PARSER" -r \
      --arg feat "$_feature" \
      '.features[] | select(.id == $feat) | .options // {} | to_entries[] | "--\(.key)", "\(.value | tostring)"' \
      "$_MANIFEST"
  )

  echo "" >&2
  echo "▶️  [${_feature}] Installing..." >&2
  if _run_feature "$_feature" "${_opts[@]+"${_opts[@]}"}"; then
    _passed+=("$_feature")
    echo "✅ [${_feature}] Done" >&2
  else
    _failed+=("$_feature")
    echo "⛔ [${_feature}] FAILED" >&2
  fi
done

# ── Summary ───────────────────────────────────────────────────────────────────
_total=$(("${#_passed[@]}" + "${#_failed[@]}"))
echo "" >&2
echo "── Summary (${_total} features) ─────────────────────────────────────────" >&2
for _f in "${_passed[@]+"${_passed[@]}"}"; do echo "  ✅ ${_f}" >&2; done
for _f in "${_failed[@]+"${_failed[@]}"}"; do echo "  ⛔ ${_f}" >&2; done
echo "" >&2

if [[ "${#_failed[@]}" -gt 0 ]]; then
  echo "⛔ ${#_failed[@]} feature(s) failed." >&2
  exit 1
fi

echo "↩️  Script exit: sysset manifest installer" >&2
