# shellcheck shell=bash

# ── High-level steps ──────────────────────────────────────────────────────────

__install_run_script_pre() {
  if [ "$(ctx__get plat.kernel)" = "Darwin" ]; then
    bootstrap__xcode
  fi
  return 0
}

__install_run_script_run() {
  local _installer="$1"
  # Make the installer readable and all parent directories up to the tmpdir
  # root traversable; runuser switches to the install user, which must be
  # able to traverse the (mode-700) process temp tree.
  local _work_dir
  _work_dir="$(dirname "$(dirname "$_installer")")" # .../install-homebrew.XXXXX/
  file__chmod -R a+rX "$_work_dir"
  file__chmod a+x "$(dirname "$_work_dir")" # .../devfeats_XXXXX/
  local -a _env_vars=("NONINTERACTIVE=1" "HOMEBREW_PREFIX=${_RESOLVED_PREFIX}")
  [ -n "${BREW_GIT_REMOTE-}" ] && _env_vars+=("HOMEBREW_BREW_GIT_REMOTE=${BREW_GIT_REMOTE}")
  [ -n "${CORE_GIT_REMOTE-}" ] && _env_vars+=("HOMEBREW_CORE_GIT_REMOTE=${CORE_GIT_REMOTE}")
  [[ "${NO_INSTALL_FROM_API}" == true ]] && _env_vars+=("HOMEBREW_NO_INSTALL_FROM_API=1")
  logging__launch "Running Homebrew installer '${_installer}' as user '${INSTALL_USER}' (prefix='${_RESOLVED_PREFIX}')."
  _brew_run_as_install_user env "${_env_vars[@]}" /bin/bash "$_installer"
  local _installer_rc=$?
  [[ $_installer_rc == 0 ]] || {
    logging__error "Homebrew installer script exited with status ${_installer_rc}."
    return "$_installer_rc"
  }
  if [ ! -f "${_RESOLVED_PREFIX}/bin/brew" ]; then
    logging__error "Homebrew executable not found at '${_RESOLVED_PREFIX}/bin/brew' after installation."
    return 1
  fi
  logging__success "Homebrew $("${_RESOLVED_PREFIX}/bin/brew" --version | head -1) is available at '${_RESOLVED_PREFIX}/bin/brew'."
  return 0
}

uninstall_brew() {
  logging__remove "Uninstalling Homebrew at '${_RESOLVED_PREFIX}'."
  local _url="https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh"
  local _tmpfile
  _tmpfile="$(mktemp /tmp/brew_uninstall.XXXXXX.sh)"
  # shellcheck disable=SC2064
  trap "rm -f '${_tmpfile}'" RETURN
  uri__fetch_asset "$_url" --file-dest "$_tmpfile" --installer-dir "${INSTALLER_DIR}" > /dev/null
  file__chmod a+r "$_tmpfile"
  # Run as the current process (root when called from root) so it can remove
  # files in a root-provisioned prefix regardless of who owns them.
  env NONINTERACTIVE=1 /bin/bash "$_tmpfile" --path "$_RESOLVED_PREFIX"
  logging__success "Homebrew uninstalled."
  return 0
}

# ── Helper functions ──────────────────────────────────────────────────────────

# Returns the path to the Homebrew/brew git repository — distinct from the
# prefix on Intel macOS and Linux, where brew lives in ${prefix}/Homebrew.
detect_brew_repository() {
  if [ "$(ctx__get plat.kernel)" = "Darwin" ] && [ "$(ctx__get plat.machine_release)" = "arm64" ]; then
    echo "${_RESOLVED_PREFIX}"
  else
    echo "${_RESOLVED_PREFIX}/Homebrew"
  fi
  return 0
}

# enforce_options — applies post-install options unconditionally:
#   • BREW_GIT_REMOTE / CORE_GIT_REMOTE: sets git remote.origin.url on the
#     brew and homebrew-core repositories, and writes env-var export blocks to
#     shell init files (so future `brew update` calls use the same remote).
#   • NO_INSTALL_FROM_API: writes / removes HOMEBREW_NO_INSTALL_FROM_API=1
#     export block in shell init files.
enforce_options() {
  local _brew_repo _core_repo _marker_brew _marker_core _marker_api
  _brew_repo="$(detect_brew_repository)"
  _core_repo="${_brew_repo}/Library/Taps/homebrew/homebrew-core"
  _marker_brew="HOMEBREW_BREW_GIT_REMOTE (install-homebrew)"
  _marker_core="HOMEBREW_CORE_GIT_REMOTE (install-homebrew)"
  _marker_api="HOMEBREW_NO_INSTALL_FROM_API (install-homebrew)"

  # --- brew git remote ---
  if [ -n "${BREW_GIT_REMOTE-}" ]; then
    logging__info "Setting brew git remote to '${BREW_GIT_REMOTE}'."
    if [ -d "${_brew_repo}/.git" ]; then
      git -C "$_brew_repo" remote set-url origin "$BREW_GIT_REMOTE"
    else
      logging__warn "brew repository not found at '${_brew_repo}'; skipping git remote set."
    fi
  fi
  _sync_init_files "$_marker_brew" ${BREW_GIT_REMOTE:+"export HOMEBREW_BREW_GIT_REMOTE=\"${BREW_GIT_REMOTE}\""}

  # --- core git remote ---
  if [ -n "${CORE_GIT_REMOTE-}" ]; then
    logging__info "Setting homebrew-core git remote to '${CORE_GIT_REMOTE}'."
    if [ -d "${_core_repo}/.git" ]; then
      git -C "$_core_repo" remote set-url origin "$CORE_GIT_REMOTE"
    else
      logging__warn "homebrew-core tap not present at '${_core_repo}'; skipping git remote set."
    fi
  fi
  _sync_init_files "$_marker_core" ${CORE_GIT_REMOTE:+"export HOMEBREW_CORE_GIT_REMOTE=\"${CORE_GIT_REMOTE}\""}

  # --- HOMEBREW_NO_INSTALL_FROM_API ---
  if [[ "${NO_INSTALL_FROM_API}" == true ]]; then
    logging__info "Persisting HOMEBREW_NO_INSTALL_FROM_API=1."
    _sync_init_files "$_marker_api" "export HOMEBREW_NO_INSTALL_FROM_API=1"
  else
    _sync_init_files "$_marker_api"
  fi

  return 0
}

# _sync_init_files <marker> [content]
# Calls shell__sync_block for the relevant init files: system-wide profile.d
# when running as root on Linux, or INSTALL_USER's home otherwise.
# If content is given, writes/updates the block; if absent, removes it.
_sync_init_files() {
  local _marker="$1"
  local _content="${2-}"
  local _has_content=false
  [ $# -ge 2 ] && _has_content=true
  local _files _slug _is_root=false
  ! users__is_user_path "${_RESOLVED_PREFIX}" && _is_root=true

  if [ "$_is_root" = true ] && [ "$(ctx__get plat.kernel)" != "Darwin" ]; then
    _slug="$(echo "$_marker" | tr ' ()' '_' | tr -s '_' | tr '[:upper:]' '[:lower:]')"
    _files="$(shell__system_path_files --profile_d "${_slug}.sh")"
  else
    _files="$(shell__user_path_files --home "$(users__resolve_home "$INSTALL_USER")")"
  fi
  if [ "$_has_content" = true ]; then
    shell__sync_block --files "$_files" --marker "$_marker" --content "$_content"
  else
    shell__sync_block --files "$_files" --marker "$_marker"
  fi
  return 0
}

# _brew_run_as_install_user <cmd> [args...]
# Run a command as INSTALL_USER when the current process is root and
# the install user is not root. Uses runuser(1) on Linux (no sudo config
# needed for root) and sudo on macOS (runuser is absent there).
_brew_run_as_install_user() {
  users__run_as "${INSTALL_USER}" -- "$@"
}

__init_args_post() {
  if [ -z "${INSTALL_USER:-}" ]; then
    if users__is_root && [ "$(ctx__get plat.kernel)" != "Darwin" ]; then
      # Linux root without an explicit install_user: always use the linuxbrew
      # system account regardless of _REMOTE_USER / _CONTAINER_USER context.
      # The official Homebrew installer hardcodes /home/linuxbrew/.linuxbrew
      # on Linux; that path must be owned by a system (non-login) account so
      # shell__run_prefix_discovery treats it as system-scope and writes to
      # /etc/profile.d rather than the remote user's dotfiles.
      logging__info "Linux root: using 'linuxbrew' as install_user."
      INSTALL_USER="linuxbrew"
    else
      # Non-root, or macOS root: resolve via SUDO_USER → _REMOTE_USER → id -un.
      INSTALL_USER="$(users__get_current)"
    fi
  fi
  # Homebrew cannot run as root. macOS root still needs a non-system user.
  if [ "$INSTALL_USER" = "root" ]; then
    if [ "$(ctx__get plat.kernel)" = "Darwin" ]; then
      local _u
      _u="$(dscl . list /Users 2> /dev/null |
        grep -v -E '^(_|daemon|nobody|root|Guest)' |
        head -1)" || true
      if [ -n "$_u" ]; then
        logging__info "macOS root: using first non-system user '${_u}' as install_user."
        INSTALL_USER="$_u"
      else
        logging__error "Running as root on macOS but no non-root user found."
        logging__info "Set the 'install_user' option to a non-root user account."
        return 1
      fi
    else
      logging__info "Linux: falling back to 'linuxbrew' as install_user."
      INSTALL_USER="linuxbrew"
    fi
  fi
  logging__info "Install user: '${INSTALL_USER}'."
  if [ "$INSTALL_USER" = "linuxbrew" ] && [ "$(ctx__get plat.kernel)" != "Darwin" ] && users__is_root; then
    # Create the linuxbrew system account before prefix resolution expands ${HOME} for that user.
    _ensure_linuxbrew_user
  fi
}

_ensure_linuxbrew_user() {
  # Create the linuxbrew system user if it does not yet exist.
  if id linuxbrew &> /dev/null; then
    return 0
  fi
  logging__info "Creating 'linuxbrew' system user."
  users__create_system_user linuxbrew --home /home/linuxbrew --shell /bin/bash
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "Failed to create 'linuxbrew' system user."
    return "$_rc"
  }
  # Ubuntu 22.04+ creates home directories with mode 750; make the home
  # world-traversable so other users can reach the brew binary.
  file__chmod 755 /home/linuxbrew
}

validate_install_user() {
  local _user="$1"
  # Non-root caller cannot impersonate another user.
  local _cur
  _cur="$(users__get_current --no-sudo)"
  if ! users__is_root && [ "$_user" != "$_cur" ]; then
    logging__error "install_user='${_user}' differs from the current user '${_cur}'."
    logging__info "Only root can install Homebrew for a different user."
    return 1
  fi
  # macOS: root is never a valid Homebrew owner.
  if [ "$(ctx__get plat.kernel)" = "Darwin" ] && [ "$_user" = "root" ]; then
    logging__error "The Homebrew installer refuses to run as root on macOS."
    logging__info "Set 'install_user' to a non-root user account."
    return 1
  fi
  # Linux: root is allowed only when explicitly requested; warn about reliability.
  if [ "$(ctx__get plat.kernel)" != "Darwin" ] && [ "$_user" = "root" ]; then
    logging__warn "install_user='root' on Linux: the official Homebrew installer may refuse"
    logging__info "root in some container environments (Docker BuildKit + cgroup v2)."
    logging__info "Consider using a non-root install_user."
  fi
  # Target user must already exist (except 'linuxbrew', created later if needed).
  if [ "$_user" != "linuxbrew" ] && [ "$_user" != "root" ] && ! id "$_user" &> /dev/null; then
    logging__error "install_user='${_user}' does not exist on this system."
    return 1
  fi
  return 0
}

# prepare_prefix_if_needed <prefix> <install_user>
# Linux + root only: creates the linuxbrew system user if needed, then ensures
# the prefix directory exists and is owned by the install user.
# No-op on macOS (the Homebrew installer manages /opt/homebrew and /usr/local).
# No-op when not running as root (target user is responsible for their own home).
prepare_prefix_if_needed() {
  local _install_prefix="$1" _user="$2"
  if [ "$_user" = "linuxbrew" ]; then
    _ensure_linuxbrew_user
  fi
  # Create the prefix directory if it does not exist yet.
  if [ ! -e "$_install_prefix" ]; then
    logging__info "Creating prefix directory '${_install_prefix}' owned by '${_user}'."
    file__mkdir "$_install_prefix"
    file__chmod 755 "$(dirname "$_install_prefix")" 2> /dev/null || true
    file__chown "$_user" "$_install_prefix"
    return 0
  fi
  # Prefix already exists — inspect ownership.
  local _owner
  _owner="$(stat -c '%U' "$_install_prefix" 2> /dev/null || echo '')"
  if [ "$_owner" = "$_user" ]; then
    logging__info "Prefix '${_install_prefix}' already owned by '${_user}'."
    return 0
  fi
  # A brew binary is present: ownership mismatch is handled by if_exists.
  if [ -f "${_install_prefix}/bin/brew" ]; then
    logging__warn "Prefix '${_install_prefix}' is owned by '${_owner}' (not '${_user}')."
    logging__info "Existing installation will be handled by if_exists='${IF_EXISTS}'."
    return 0
  fi
  # Empty directory: safe to re-own.
  if [ -z "$(ls -A "$_install_prefix" 2> /dev/null)" ]; then
    logging__info "Re-owning empty prefix '${_install_prefix}' to '${_user}'."
    file__chown "$_user" "$_install_prefix"
    return 0
  fi
  # Non-empty directory owned by someone else with no brew binary — conflict.
  logging__error "Prefix '${_install_prefix}' is non-empty and owned by '${_owner}' (not '${_user}')."
  logging__info "Remove or empty the directory first, or set a different prefix."
  return 1
}

# ── Template hook implementations ─────────────────────────────────────────────

__verify_system_requirements_post() {
  validate_install_user "$INSTALL_USER"
}

__resolve_input_prefixes_post() {
  if [ "$(ctx__get plat.kernel)" != "Darwin" ] && ! users__is_user_path "${_RESOLVED_PREFIX}"; then
    prepare_prefix_if_needed "$_RESOLVED_PREFIX" "$INSTALL_USER"
  fi
  # On macOS the prefix (/opt/homebrew) is not under $HOME but is user-owned;
  # force user scope so activation writes to INSTALL_USER's home, not /etc/*.
  # On Linux a non-$HOME prefix (rare) is a genuine system install, so keep the
  # auto-determined scope (system) there.
  if [ "$(ctx__get plat.kernel)" = "Darwin" ]; then
    PREFIX_SCOPE=user
  fi
}

__uninstall_run__() {
  uninstall_brew
}

__install_finish_post() {
  enforce_options
  if [[ "$UPDATE" == true ]]; then
    logging__info "Running 'brew update'."
    _ospkg__run_network --operation update _brew_run_as_install_user "${_RESOLVED_PREFIX}/bin/brew" update
    local _update_rc=$?
    [[ $_update_rc == 0 ]] || {
      logging__error "brew update failed after installation."
      return "$_update_rc"
    }
    logging__success "brew update completed."
  fi
  logging__info "Running 'brew doctor' (warnings only)."
  _brew_run_as_install_user "${_RESOLVED_PREFIX}/bin/brew" doctor 2>&1 || true
}

# Remove env-var export blocks written by enforce_options.
# shellcheck disable=SC2329,SC2317
__uninstall_finish_post() {
  _sync_init_files "HOMEBREW_BREW_GIT_REMOTE (install-homebrew)"
  _sync_init_files "HOMEBREW_CORE_GIT_REMOTE (install-homebrew)"
  _sync_init_files "HOMEBREW_NO_INSTALL_FROM_API (install-homebrew)"
}
