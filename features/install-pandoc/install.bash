# install-pandoc feature hooks.
#
# pandoc declares prefix.bins=[pandoc, pandoc-server, pandoc-lua], but the two
# companions are argv[0] aliases the release tarball ships as symlinks (which the
# binary extractor drops) and the OS package omits entirely. The binary method's
# companions are created by the framework itself (BINARY_COMPANION_BINS in
# __install_run_binary__). The OS package method has no prefix/companion
# machinery (prefix.applies_when=[binary]), so recreate them here next to the
# packaged pandoc.
__install_run_package_post() {
  local _pandoc
  _pandoc="$(command -v pandoc 2> /dev/null || true)"
  if [[ -z "${_pandoc}" ]]; then
    logging__warn "pandoc not found on PATH after package install; skipping companions."
    return 0
  fi
  local _dir _name
  _dir="$(dirname "${_pandoc}")"
  for _name in pandoc-server pandoc-lua; do
    ln -sf pandoc "${_dir}/${_name}"
  done
  logging__info "Linked pandoc-server + pandoc-lua companions in '${_dir}'."
}
