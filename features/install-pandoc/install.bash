# install-pandoc feature hooks.
#
# pandoc ships `pandoc-server` and `pandoc-lua` as symlinks to `pandoc` in its
# release tarball (the binary dispatches on argv[0]). The release extractor
# (`binary_src`) copies only the real `pandoc` file and drops the symlinks, and
# the OS `pandoc` package ships only `pandoc` too — so neither method delivers
# the two companion executables on its own. Recreate them next to the installed
# `pandoc` so all three declared `prefix.bins` are always present.

# _pandoc_link_companions <dir> — create pandoc-server + pandoc-lua symlinks to
# `pandoc` inside <dir> (which must already contain the `pandoc` binary).
_pandoc_link_companions() {
  local _dir="$1"
  local _name
  for _name in pandoc-server pandoc-lua; do
    ln -sf pandoc "${_dir}/${_name}"
  done
  logging__info "Linked pandoc-server + pandoc-lua companions in '${_dir}'."
}

# binary method: the real pandoc lands at ${_RESOLVED_PREFIX}/bin/pandoc. Create
# the companions there BEFORE __install_finish__ runs, so the framework's
# prefix-discovery symlinks all three onto PATH (and they exist inside a custom
# prefix as well).
__install_run_binary_post() {
  _pandoc_link_companions "${_RESOLVED_PREFIX}/bin"
}

# package method: the OS package installs pandoc to a PM-managed bin dir (no
# framework prefix machinery); add the companions right next to it, on PATH.
__install_run_package_post() {
  local _pandoc
  _pandoc="$(command -v pandoc 2> /dev/null || true)"
  if [[ -z "${_pandoc}" ]]; then
    logging__warn "pandoc not found on PATH after package install; skipping companions."
    return 0
  fi
  _pandoc_link_companions "$(dirname "${_pandoc}")"
}
