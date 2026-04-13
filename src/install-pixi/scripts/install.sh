#!/usr/bin/env bash
set -euo pipefail
_SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/ospkg.sh
. "$_SELF_DIR/_lib/ospkg.sh"
# shellcheck source=lib/logging.sh
. "$_SELF_DIR/_lib/logging.sh"
# shellcheck source=lib/github.sh
. "$_SELF_DIR/_lib/github.sh"
logging__setup
echo "↪️ Script entry: Pixi Installation Devcontainer Feature Installer" >&2
trap 'logging__cleanup' EXIT

# ── Constants ────────────────────────────────────────────────────────────────
_PIXI_RELEASES_BASE_URL="https://github.com/prefix-dev/pixi/releases/download"

if [ "$#" -gt 0 ]; then
  echo "ℹ️ Script called with arguments: $*" >&2
  DEBUG=""
  INSTALL_PATH=""
  LOGFILE=""
  VERSION=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --debug)
        shift
        DEBUG=true
        echo "📩 Read argument 'debug': '${DEBUG}'" >&2
        ;;
      --install_path)
        shift
        INSTALL_PATH="$1"
        echo "📩 Read argument 'install_path': '${INSTALL_PATH}'" >&2
        shift
        ;;
      --logfile)
        shift
        LOGFILE="$1"
        echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2
        shift
        ;;
      --version)
        shift
        VERSION="$1"
        echo "📩 Read argument 'version': '${VERSION}'" >&2
        shift
        ;;
      --*)
        echo "⛔ Unknown option: '${1}'" >&2
        exit 1
        ;;
      *)
        echo "⛔ Unexpected argument: '${1}'" >&2
        exit 1
        ;;
    esac
  done
else
  echo "ℹ️ Script called with no arguments. Read environment variables." >&2
  [ "${DEBUG+defined}" ] && echo "📩 Read argument 'debug': '${DEBUG}'" >&2
  [ "${INSTALL_PATH+defined}" ] && echo "📩 Read argument 'install_path': '${INSTALL_PATH}'" >&2
  [ "${LOGFILE+defined}" ] && echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2
  [ "${VERSION+defined}" ] && echo "📩 Read argument 'version': '${VERSION}'" >&2
fi
[[ "${DEBUG:-}" == true ]] && set -x
[ -z "${DEBUG-}" ] && {
  echo "ℹ️ Argument 'DEBUG' set to default value 'false'." >&2
  DEBUG=false
}
[ -z "${INSTALL_PATH-}" ] && {
  echo "ℹ️ Argument 'INSTALL_PATH' set to default value '/usr/local/bin'." >&2
  INSTALL_PATH="/usr/local/bin"
}
[ -z "${LOGFILE-}" ] && {
  echo "ℹ️ Argument 'LOGFILE' set to default value ''." >&2
  LOGFILE=""
}
[ -z "${VERSION-}" ] && {
  echo "ℹ️ Argument 'VERSION' set to default value '0.66.0'." >&2
  VERSION="0.66.0"
}

ospkg__run --manifest "${_SELF_DIR}/../dependencies/base.yaml" --check_installed

pixi_bin="${INSTALL_PATH}/pixi"

if [[ "$VERSION" == "latest" ]]; then
  echo "ℹ️ Resolving latest Pixi release tag from GitHub API." >&2
  VERSION="$(github__latest_tag prefix-dev/pixi)" || {
    echo "⛔ Failed to resolve latest Pixi version." >&2
    exit 1
  }
  # Strip the leading 'v' prefix from the tag (e.g. v0.66.0 → 0.66.0).
  VERSION="${VERSION#v}"
  echo "ℹ️ Resolved Pixi version: '${VERSION}'." >&2
fi

net__fetch_url_file \
  "${_PIXI_RELEASES_BASE_URL}/v${VERSION}/pixi-$(os__arch)-unknown-linux-musl" \
  "$pixi_bin"

chmod +rx "$pixi_bin"

pixi info

echo "↩️ Script exit: Pixi Installation Devcontainer Feature Installer" >&2
