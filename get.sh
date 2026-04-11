#!/bin/sh
# get.sh — Download and install a single sysset feature from a GitHub Release.
#
# Usage:
#   get.sh <feature> [--tag <release-tag>] [<feature-install-options>...]
#
#   <feature>               Feature to install (e.g. install-pixi, install-shell)
#   --tag <tag>             Override the release tag (default: stamped at build time)
#   <feature-install-options>  Forwarded verbatim to the feature's install.sh
#
# Examples:
#   get.sh install-pixi --version 0.66.0
#   get.sh install-shell --shell zsh --install_ohmyzsh true
#   get.sh install-pixi --tag v1.2.0 --version 0.66.0
#
# This script is version-stamped at release build time (@@RELEASE_TAG@@ is
# replaced with the actual release tag by build-artifacts.sh). Running it
# without --tag always installs from the same release it was bundled with.
set -eu

SYSSET_RELEASE_TAG="@@RELEASE_TAG@@"
SYSSET_REPO="quantized8/sysset"

__usage__() {
  cat >&2 << EOF
Usage: get.sh <feature> [--tag <release-tag>] [<feature-install-options>...]

  <feature>                 Feature to install (e.g. install-pixi, install-shell)
  --tag <tag>               Override release tag (default: ${SYSSET_RELEASE_TAG})
  <feature-install-options> Passed verbatim to the feature installer

Examples:
  get.sh install-pixi --version 0.66.0
  get.sh install-shell --shell zsh
  get.sh install-pixi --tag v1.2.0 --version 0.66.0
EOF
  exit 0
}

# ── Argument parsing ──────────────────────────────────────────────────────────

[ "$#" -eq 0 ] && __usage__

_feature=""
_tag="$SYSSET_RELEASE_TAG"

# First positional arg = feature name.
case "$1" in
  --help | -h) __usage__ ;;
  --*)
    echo "⛔ Expected a feature name as the first argument, got: '${1}'" >&2
    exit 1
    ;;
  *)
    _feature="$1"
    shift
    ;;
esac

# Consume --tag <value> before any remaining feature-install options.
# Stop at the first arg that is not --tag (rest forwarded as-is).
while [ "$#" -gt 0 ]; do
  case "$1" in
    --tag)
      shift
      if [ "$#" -eq 0 ]; then
        echo "⛔ --tag requires a value." >&2
        exit 1
      fi
      _tag="$1"
      shift
      ;;
    *) break ;;
  esac
done
# "$@" now contains only the feature-install options.

# ── Detect fetch tool ─────────────────────────────────────────────────────────

if command -v curl > /dev/null 2>&1; then
  _fetch_tool="curl"
elif command -v wget > /dev/null 2>&1; then
  _fetch_tool="wget"
else
  echo "⛔ Neither curl nor wget found. Install one and retry." >&2
  exit 1
fi

# ── Download ──────────────────────────────────────────────────────────────────

_tmpdir="$(mktemp -d)"
trap 'rm -rf "$_tmpdir"' EXIT

_url="${SYSSET_BASE_URL:-https://github.com/${SYSSET_REPO}/releases/download/${_tag}}/sysset-${_feature}.tar.gz"
echo "↪️  Downloading sysset-${_feature} @ ${_tag} ..." >&2

if [ "$_fetch_tool" = "curl" ]; then
  curl -fsSL "$_url" -o "$_tmpdir/feature.tar.gz"
else
  wget -qO "$_tmpdir/feature.tar.gz" "$_url"
fi

# ── Extract and run ───────────────────────────────────────────────────────────

tar -xzf "$_tmpdir/feature.tar.gz" -C "$_tmpdir"

# The tarball root contains a POSIX sh bootstrap (install.sh) that finds
# bash>=4 (installing it if necessary) and execs scripts/install.sh "$@".
sh "$_tmpdir/install.sh" "$@"
