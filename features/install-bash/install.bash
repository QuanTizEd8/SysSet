# shellcheck shell=bash

# shellcheck disable=SC2034,SC2329,SC2317
__init_args_post() {
  # install.sh may have bootstrapped bash (via PM or source compile) as an
  # implementation detail to run this feature script.  That bootstrap is invisible to
  # the user — they had no bash before.  Override IF_EXISTS to 'reinstall' so the
  # feature always installs the version the user actually requested, regardless of
  # whether if_exists is skip/fail/reinstall.  The override only fires when bootstrap
  # vars are present; if the user genuinely had bash before, neither variable is set
  # and if_exists behaves normally.
  if [[ -n "${_BASH_INSTALLED_BY_PM:-}" ]] || [[ -n "${_BASH_INSTALLED_INTERNALLY:-}" ]]; then
    IF_EXISTS="reinstall"
  fi
}

# shellcheck disable=SC2329,SC2317
__configure_user() {
  # Per-user hook (invoked once per resolved user by __feat_do_configure_users__,
  # from both __install_finish__ and the if_exists=skip branch). Sets the login
  # shell to the bash this feature installed when set_login_shell is true.
  [[ "${SET_LOGIN_SHELL:-false}" == true ]] || return 0
  local _username="$1" _bash
  _bash="$(command -v bash 2> /dev/null || true)"
  if [[ -z "${_bash}" && "${METHOD:-}" == source && -n "${_RESOLVED_PREFIX:-}" ]]; then
    _bash="${_RESOLVED_PREFIX}/bin/bash"
  fi
  if [[ -z "${_bash}" ]]; then
    logging__warn "set_login_shell=true but no bash binary found; skipping chsh for '${_username}'."
    return 0
  fi
  users__set_login_shell "${_bash}" "${_username}"
}

# shellcheck disable=SC2329,SC2317
__skip_post() {
  # Safety net: if somehow the feature reaches skip with bootstrap vars still set
  # (e.g. a future if_exists mode we don't anticipate), keep the bootstrap bash.
  [[ -n "${_BASH_INSTALLED_BY_PM:-}" ]] && unset _BASH_INSTALLED_BY_PM
  [[ -n "${_BASH_BIN:-}" ]] && install__promote_path_to_user "bash-bootstrap" "${_BASH_BIN}"
}

# shellcheck disable=SC2329,SC2317
__install_finish_post() {
  # 1. Register bash in /etc/shells for source system-wide installs.
  #    Package installs handle /etc/shells registration themselves.
  if [[ "${METHOD}" == "source" && "${PREFIX_SCOPE}" == "system" ]]; then
    local _bash="${_RESOLVED_PREFIX}/bin/bash"
    [[ -x "${_bash}" ]] || return 0
    local _shells_file=/etc/shells
    [[ -f /usr/share/defaults/etc/shells ]] && _shells_file=/usr/share/defaults/etc/shells
    if [[ -f "${_shells_file}" ]] && ! grep -qx "${_bash}" "${_shells_file}" 2> /dev/null; then
      printf '%s\n' "${_bash}" | file__append_privileged "${_shells_file}"
      logging__info "Added '${_bash}' to '${_shells_file}'."
    fi
  fi

  # 2. Prevent the bootstrap cleanup at __exit__ from removing the feature-installed bash.
  #    install.sh may have installed bash (by PM or from source) before the feature ran;
  #    now that the feature owns bash, the bootstrap artifact is superseded.
  #
  #    Case A – package method: clear PM tracking so __exit__ does not run
  #    ospkg__remove_user bash and uninstall what the feature just installed.
  if [[ "${METHOD}" == "package" ]] && [[ -n "${_BASH_INSTALLED_BY_PM:-}" ]]; then
    unset _BASH_INSTALLED_BY_PM
  fi

  #    Case B – source method to the same path: if the bootstrap source binary
  #    (_BASH_BIN) is the same file the feature just installed, promote it out of
  #    ospkg resource cleanup tracking so ospkg__cleanup_resources does not delete it.
  if [[ "${METHOD}" == "source" ]] && [[ -n "${_BASH_BIN:-}" ]]; then
    local _feature_bash="${_RESOLVED_PREFIX}/bin/bash"
    if [[ "${_BASH_BIN}" == "${_feature_bash}" ]]; then
      install__promote_path_to_user "bash-bootstrap" "${_feature_bash}"
    fi
  fi
}

# shellcheck disable=SC2329,SC2317
__uninstall_run_prefix_post() {
  # Remove bash-specific files not covered by the default prefix binary removal.
  local _prefix="${_RESOLVED_PREFIX}"
  [[ -n "${_prefix}" && "${_prefix}" != "/" ]] || return 0
  file__rm -f "${_prefix}/bin/bashbug"
  file__rm -rf "${_prefix}/share/doc/bash/"
  file__rm -f "${_prefix}/share/info/bash.info"
}
