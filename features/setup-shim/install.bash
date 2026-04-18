_SHIM_BIN="/usr/local/share/setup-shim/bin"
_FILES_DIR="${_BASE_DIR}/files"

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

exit 0
