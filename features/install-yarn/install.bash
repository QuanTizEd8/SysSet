# shellcheck shell=bash

__install_run_npm__() {
  logging__install "Installing Yarn globally via npm."
  if [ "${YARN_VERSION}" = "latest" ] && command -v corepack > /dev/null 2>&1; then
    logging__install "Enabling Yarn via corepack."
    local -a _corepack_args=(enable)
    # corepack's default shim location is node's own bin dir, which ignores the
    # feature's prefix. Point --install-directory at the resolved prefix bin so
    # yarn lands where the prefix machinery (and everything downstream) expects.
    # _RESOLVED_PREFIX is the prefix the framework resolved (same variable the
    # generic __install_run_npm__ passes to `npm --prefix`).
    if [[ -v _RESOLVED_PREFIX ]]; then
      local _yarn_bindir="${_RESOLVED_PREFIX}/${PREFIX_BIN_DIR:-bin}"
      file__mkdir "${_yarn_bindir}"
      _corepack_args+=(--install-directory "${_yarn_bindir}")
    fi
    _corepack_args+=(yarn)
    corepack "${_corepack_args[@]}" || {
      logging__error "Failed to enable Yarn via corepack."
      return 1
    }
    logging__success "Yarn enabled via corepack."
    return 0
  fi

  local _pkg="yarn"
  [ "${YARN_VERSION}" != "latest" ] && _pkg+="@${YARN_VERSION}"

  local -a _install_args=(install -g)
  [[ -v _RESOLVED_PREFIX ]] && _install_args+=(--prefix "${_RESOLVED_PREFIX}")
  _install_args+=("${_pkg}")

  npm "${_install_args[@]}" || {
    logging__error "Failed to install Yarn '${_pkg}' via npm."
    return 1
  }
  logging__success "Yarn '${_pkg}' installed via npm."
}
