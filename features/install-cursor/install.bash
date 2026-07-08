# shellcheck shell=bash

# Determine the user to run the Cursor installer for.
# The official installer writes to ${HOME}/.local — must run as the target user.
# shellcheck disable=SC2329,SC2317
__init_args_post() {
  [ -n "${INSTALL_USER:-}" ] || {
    INSTALL_USER="$(users__get_current)"
    logging__info "install_user unset; defaulting to '${INSTALL_USER}'."
  }
}

# Probe for an existing Cursor CLI installation in the install user's home or
# on PATH (covers /usr/local/bin wrappers created by root builds).
# shellcheck disable=SC2329,SC2317
__detect_existing_path_post() {
  [ -n "${_FEAT_EXISTING_PATH}" ] && return 0
  local _home
  _home="$(users__resolve_home "${INSTALL_USER}")"
  local _agent="${_home}/.local/bin/agent"
  if [ -L "${_agent}" ] || [ -f "${_agent}" ]; then
    _FEAT_EXISTING_PATH="${_agent}"
    logging__detect "Found Cursor CLI agent at '${_agent}'."
    return 0
  fi
  # Fall back to PATH (picks up /usr/local/bin/agent from root builds).
  _FEAT_EXISTING_PATH="$(command -v agent 2> /dev/null || true)"
  [[ -n "${_FEAT_EXISTING_PATH}" ]] &&
    logging__detect "Found Cursor CLI agent on PATH at '${_FEAT_EXISTING_PATH}'."
  # Detection is best-effort: finding no existing agent (a fresh install) is the
  # normal case and must not fail the hook under errexit.
  return 0
}

# Override the script runner to execute the Cursor installer as the install
# user. The official installer creates ~/.local/share/cursor-agent and
# ~/.local/bin/{agent,cursor-agent} symlinks without accepting any arguments.
# shellcheck disable=SC2329,SC2317
__install_run_script_run() {
  local _installer="$1"
  local _home
  _home="$(users__resolve_home "${INSTALL_USER}")"

  # Make the downloaded script accessible from the target user's context.
  local _work_dir
  _work_dir="$(dirname "$(dirname "$_installer")")"
  file__chmod -R a+rX "$_work_dir"
  file__chmod a+x "$(dirname "$_work_dir")" 2> /dev/null || true

  logging__info "Running Cursor CLI installer as user '${INSTALL_USER}' (home: ${_home})..."
  if [ "${INSTALL_USER}" = "$(users__get_current --no-sudo)" ]; then
    HOME="${_home}" bash "${_installer}"
  else
    users__run_privileged su "${INSTALL_USER}" -c "HOME='${_home}' bash '${_installer}'"
  fi

  local _agent_bin="${_home}/.local/bin/agent"
  if [ ! -L "${_agent_bin}" ] && [ ! -f "${_agent_bin}" ]; then
    logging__error "Cursor CLI 'agent' not found at '${_agent_bin}' after installation."
    return 1
  fi
  logging__success "Cursor CLI installed for user '${INSTALL_USER}'."
}

# Remove the Cursor CLI installation for the install user.
# Global /usr/local/bin wrappers are cleaned up by _cursor_remove_global_symlinks.
# shellcheck disable=SC2329,SC2317
__uninstall_run__() {
  local _home
  _home="$(users__resolve_home "${INSTALL_USER}")"
  logging__remove "Removing Cursor CLI for user '${INSTALL_USER}'..."
  local _cmd
  for _cmd in agent cursor-agent; do
    local _link="${_home}/.local/bin/${_cmd}"
    { [ -L "${_link}" ] || [ -f "${_link}" ]; } && file__rm -f "${_link}" || true
  done
  if [ -d "${_home}/.local/share/cursor-agent" ]; then
    file__rm -rf "${_home}/.local/share/cursor-agent"
  fi
  _cursor_remove_global_symlinks
  logging__success "Cursor CLI removed."
}

# Create /usr/local/bin wrappers so 'agent' and 'cursor-agent' are
# discoverable system-wide when the feature runs as root.
_cursor_create_global_symlinks() {
  users__is_root || {
    logging__skip "Not running as root; skipping global /usr/local/bin symlinks."
    return 0
  }
  local _home
  _home="$(users__resolve_home "${INSTALL_USER}")"
  local _cmd
  for _cmd in agent cursor-agent; do
    local _src="${_home}/.local/bin/${_cmd}"
    if [ -L "${_src}" ] || [ -f "${_src}" ]; then
      logging__info "Symlinking ${_src} → /usr/local/bin/${_cmd}"
      users__run_privileged ln -sf "${_src}" "/usr/local/bin/${_cmd}"
    fi
  done
}

# Remove the /usr/local/bin wrappers created by _cursor_create_global_symlinks.
# shellcheck disable=SC2329,SC2317
_cursor_remove_global_symlinks() {
  users__is_root || {
    logging__skip "Not running as root; skipping global symlink removal."
    return 0
  }
  local _cmd
  for _cmd in agent cursor-agent; do
    local _glnk="/usr/local/bin/${_cmd}"
    [ -L "${_glnk}" ] && users__run_privileged rm -f "${_glnk}" || true
  done
}

# shellcheck disable=SC2329,SC2317
__install_finish_post() {
  logging__install "Creating global Cursor CLI symlinks (if applicable)."
  _cursor_create_global_symlinks
}

# shellcheck disable=SC2329,SC2317
__skip_post() {
  logging__install "Refreshing global Cursor CLI symlinks (if_exists=skip)."
  _cursor_create_global_symlinks
}
