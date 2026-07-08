# shellcheck shell=bash

__install_run_npm__() {
  logging__install "Installing Yarn globally via npm."
  if [ "${YARN_VERSION}" = "latest" ] && command -v corepack > /dev/null 2>&1; then
    logging__install "Enabling Yarn via corepack."
    corepack enable || {
      logging__error "Failed to enable Yarn via corepack."
      return 1
    }
    logging__success "Yarn enabled via corepack."
    return 0
  fi

  local _pkg="yarn"
  [ "${YARN_VERSION}" != "latest" ] && _pkg+="@${YARN_VERSION}"

  local -a _install_args=(install -g)
  [[ -n "${_FEAT_CONTRACT_PREFIX_VAR:-}" && -n "${!_FEAT_CONTRACT_PREFIX_VAR:-}" ]] &&
    _install_args+=(--prefix "${!_FEAT_CONTRACT_PREFIX_VAR}")
  _install_args+=("${_pkg}")

  npm "${_install_args[@]}" || {
    logging__error "Failed to install Yarn '${_pkg}' via npm."
    return 1
  }
  logging__success "Yarn '${_pkg}' installed via npm."
}
