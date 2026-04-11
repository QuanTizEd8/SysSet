#!/usr/bin/env bash
# install.sh — runs as root at image build time.
#
# Copies enabled shim scripts into a dedicated directory that is prepended
# to PATH via containerEnv in devcontainer-feature.json.  This ensures the
# shims always shadow any real binary of the same name, without colliding
# with other files in /usr/local/bin.
#
# Feature options (injected as environment variables by the tooling):
#   CODE, DEVCONTAINER_INFO, SYSTEMCTL, DEBUG, LOGFILE
set -e

_SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
_BASE_DIR="$(cd "$_SELF_DIR/.." && pwd)"
_SHIM_BIN="/usr/local/share/setup-shim/bin"
_FILES_DIR="${_BASE_DIR}/files"

# ---------------------------------------------------------------------------
# Debug / logging
# ---------------------------------------------------------------------------
if [ "${DEBUG:-false}" = "true" ]; then
  set -x
fi

# shellcheck source=_lib/logging.sh
. "$_SELF_DIR/_lib/logging.sh"
logging::setup
trap 'logging::cleanup' EXIT

# ---------------------------------------------------------------------------
# Install shims
# ---------------------------------------------------------------------------
mkdir -p "${_SHIM_BIN}"

install_shim() {
  _src="${_FILES_DIR}/$1"
  _dst="${_SHIM_BIN}/$1"
  if [ ! -f "$_src" ]; then
    echo "setup-shim: source file not found: ${_src}" >&2
    exit 1
  fi
  cp "$_src" "$_dst"
  chmod +rx "$_dst"
  echo "  ✅ $1 → ${_dst}"
  return
}

if [ "${CODE:-true}" = "true" ]; then
  install_shim "code"
fi

if [ "${DEVCONTAINER_INFO:-true}" = "true" ]; then
  install_shim "devcontainer-info"
fi

if [ "${SYSTEMCTL:-true}" = "true" ]; then
  install_shim "systemctl"
fi

echo "setup-shim: done."
exit 0
