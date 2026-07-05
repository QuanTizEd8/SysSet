# shellcheck shell=bash

# shellcheck disable=SC2329,SC2317
__configure_user() {
  # Per-user hook (invoked once per resolved user by __feat_do_configure_users__,
  # from both __install_finish__ and the if_exists=skip branch). Sets the login
  # shell to the zsh this feature installed when set_login_shell is true.
  [[ "${SET_LOGIN_SHELL:-false}" == true ]] || return 0
  local _username="$1" _zsh
  _zsh="$(command -v zsh 2> /dev/null || true)"
  if [[ -z "${_zsh}" && "${METHOD:-}" == source && -n "${_RESOLVED_PREFIX:-}" ]]; then
    _zsh="${_RESOLVED_PREFIX}/bin/zsh"
  fi
  if [[ -z "${_zsh}" ]]; then
    logging__warn "set_login_shell=true but no zsh binary found; skipping chsh for '${_username}'."
    return 0
  fi
  users__set_login_shell "${_zsh}" "${_username}"
}

# shellcheck disable=SC2329,SC2317
__install_finish_post() {
  # Post-install: register the source-installed zsh binary in /etc/shells.
  # Package installs handle /etc/shells registration themselves.
  [[ "${METHOD}" == "source" && "${PREFIX_SCOPE}" == "system" ]] || return 0
  local _zsh="${_RESOLVED_PREFIX}/bin/zsh"
  [[ -x "${_zsh}" ]] || return 0
  local _shells_file=/etc/shells
  [[ -f /usr/share/defaults/etc/shells ]] && _shells_file=/usr/share/defaults/etc/shells
  if [[ -f "${_shells_file}" ]] && ! grep -qx "${_zsh}" "${_shells_file}" 2> /dev/null; then
    printf '%s\n' "${_zsh}" | file__append_privileged "${_shells_file}"
    logging__info "Added '${_zsh}' to '${_shells_file}'."
  fi
}

# shellcheck disable=SC2329,SC2317
__uninstall_run_prefix_post() {
  # Uninstall cleanup: remove zsh lib/share directories not covered by default prefix removal.
  local _prefix="${_RESOLVED_PREFIX}"
  [[ -n "${_prefix}" && "${_prefix}" != "/" ]] || return 0
  file__rm -rf "${_prefix}/lib/zsh/"
  file__rm -rf "${_prefix}/share/zsh/"
}
