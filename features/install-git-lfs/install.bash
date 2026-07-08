# shellcheck shell=bash

_state_dir() {
  # @brief _state_dir — Return the feature-owned persistent state directory.
  #
  # Args: none.
  # Stdout: Absolute path `${_FEAT_SHARE_DIR_ROOT}/state`.
  # Returns: 0.
  # Notes: Shared by the install script and the post-create lifecycle script.
  printf '%s/state\n' "${_FEAT_SHARE_DIR_ROOT}"
}

_state_env_file() {
  # @brief _state_env_file — Return the shell-style env file storing managed state.
  #
  # Args: none.
  # Stdout: Absolute path to the persisted configuration contract file.
  # Returns: 0.
  printf '%s/config.env\n' "$(_state_dir)"
}

_global_users_file() {
  # @brief _global_users_file — Return the newline-delimited global-user state file.
  #
  # Args: none.
  # Stdout: Absolute path to the file containing resolved users for global scope.
  # Returns: 0.
  printf '%s/global-users\n' "$(_state_dir)"
}

_emit_state_var() {
  # @brief _emit_state_var — Emit one shell-safe `NAME="value"` assignment line.
  #
  # Args:
  #   $1  Variable name to emit.
  #   $2  Value to escape for double-quoted shell assignment (optional).
  # Stdout: One assignment line suitable for sourcing via `. config.env`.
  # Returns: 0.
  # Notes: Escapes backslashes and double quotes only; all stored values are scalars.
  local _name="$1" _value="${2-}"
  _value="${_value//\\/\\\\}"
  _value="${_value//\"/\\\"}"
  printf '%s="%s"\n' "${_name}" "${_value}"
}

_effective_method() {
  # @brief _effective_method — Resolve the installation method relevant to config work.
  #
  # Args: none; reads `IF_EXISTS`, `_FEAT_EXISTING`, `_FEAT_EXISTING_METHOD`, and `METHOD`.
  # Stdout: One concrete method name.
  # Returns:
  #   0  A concrete method is available.
  #   1  Non-skip flow reached this point without a concrete `METHOD`.
  # Notes:
  #   - In `if_exists=skip`, config management operates on the already-installed tool,
  #     so `_FEAT_EXISTING_METHOD` is authoritative.
  #   - In install/update/reinstall flows, `METHOD` must already have been resolved by
  #     the template and is treated as the target method.
  local _method=""
  if [[ "${IF_EXISTS}" == "skip" && "${_FEAT_EXISTING}" == true ]]; then
    _method="${_FEAT_EXISTING_METHOD:-}"
  else
    _method="${METHOD}"
    if [[ -z "${_method}" || "${_method}" == "auto" ]]; then
      logging__error "Expected a concrete METHOD outside if_exists=skip; got '${_method:-unset}'."
      return 1
    fi
  fi
  printf '%s\n' "${_method}"
}

_resolved_scope() {
  # @brief _resolved_scope — Collapse `config_scope=auto` to an explicit Git LFS scope.
  #
  # Args: none; reads `CONFIG_SCOPE` and installer privilege state.
  # Stdout: One of `system`, `global`, `local`, `worktree`, `file`, or `none`.
  # Returns:
  #   0  Scope resolved successfully.
  #   1  `CONFIG_SCOPE` contains an unsupported value.
  case "${CONFIG_SCOPE}" in
    auto)
      if users__is_privileged; then
        printf 'system\n'
      else
        printf 'global\n'
      fi
      ;;
    system | global | local | worktree | file | none)
      printf '%s\n' "${CONFIG_SCOPE}"
      ;;
    *)
      logging__error "Unsupported config_scope='${CONFIG_SCOPE:-}'."
      return 1
      ;;
  esac
}

_scope_is_repo() {
  # @brief _scope_is_repo — Test whether a scope is repository-addressed.
  #
  # Args:
  #   $1  Candidate scope string.
  # Returns:
  #   0  Scope is `local`, `worktree`, or `file`.
  #   1  Scope is not repository-addressed.
  case "$1" in
    local | worktree | file) return 0 ;;
    *) return 1 ;;
  esac
}

_scope_needs_repo() {
  # @brief _scope_needs_repo — Test whether the requested operation needs a repo path now.
  #
  # Args:
  #   $1  Explicit scope string.
  # Returns:
  #   0  A repository is needed because the scope is repo-scoped or hooks are requested.
  #   1  No repository is needed for this configuration request.
  # Notes: `config_scope=none` always returns false.
  local _scope="$1"
  [[ "${_scope}" == "none" ]] && return 1
  _scope_is_repo "${_scope}" && return 0
  [[ "${SKIP_REPO}" == "false" ]]
}

_manual_hooks_value() {
  # @brief _manual_hooks_value — Normalize `manual_hooks` against `skip_repo`.
  #
  # Args: none; reads `MANUAL_HOOKS` and `SKIP_REPO`.
  # Stdout: `true` or `false`.
  # Returns: 0.
  # Notes:
  #   - `git lfs install --manual` has no effect together with `--skip-repo`.
  #   - Emits the explanatory log only once per script process.
  local _manual="${MANUAL_HOOKS}"
  if [[ "${SKIP_REPO}" == "true" && "${_manual}" == "true" ]]; then
    if [[ -z "${_GIT_LFS_MANUAL_HOOKS_IGNORED:-}" ]]; then
      logging__info "manual_hooks=true has no effect when skip_repo=true; ignoring."
      declare -g _GIT_LFS_MANUAL_HOOKS_IGNORED=1
    fi
    _manual=false
  fi
  printf '%s\n' "${_manual}"
}

_validate_requested_config() {
  # @brief _validate_requested_config — Reject invalid option combinations early.
  #
  # Args: none; reads the public Git LFS configuration options and runtime context.
  # Returns:
  #   0  The request is valid now or can be deferred to post-create.
  #   1  The option combination is invalid for the current execution context.
  # Notes:
  #   - `config_scope=file` requires `config_file`.
  #   - Repo-scoped configuration requires `repo_dir` unless deferred by devcontainer build.
  #   - `skip_repo=false` for `system|global` requires an immediate `repo_dir`.
  local _scope
  _scope="$(_resolved_scope)" || return 1
  [[ "${_scope}" == "none" ]] && return 0

  if [[ "${_scope}" == "file" && -z "${CONFIG_FILE:-}" ]]; then
    logging__error "config_scope=file requires config_file to be set."
    return 1
  fi

  if _scope_is_repo "${_scope}"; then
    if [[ -n "${REPO_DIR:-}" ]] || os__is_devcontainer_build; then
      return 0
    fi
    logging__error "config_scope='${_scope}' requires repo_dir outside devcontainer lifecycle execution."
    return 1
  fi

  if [[ "${SKIP_REPO}" == "false" && -z "${REPO_DIR:-}" ]]; then
    logging__error "skip_repo=false requires repo_dir when config_scope='${_scope}'."
    return 1
  fi
}

__install_init_post() {
  # @brief __install_init_post — Validate Git LFS config options during fresh install init.
  #
  # Args: none.
  # Returns: Same status as `_validate_requested_config`.
  _validate_requested_config
}

__reinstall_init_post() {
  # @brief __reinstall_init_post — Validate Git LFS config options during reinstall init.
  #
  # Args: none.
  # Returns: Same status as `_validate_requested_config`.
  _validate_requested_config
}

__update_init_post() {
  # @brief __update_init_post — Validate Git LFS config options during update init.
  #
  # Args: none.
  # Returns: Same status as `_validate_requested_config`.
  _validate_requested_config
}

_git_lfs_bin_dir() {
  # @brief _git_lfs_bin_dir — Locate the directory containing the active `git-lfs` binary.
  #
  # Args: none; reads `_RESOLVED_PREFIX`, `_FEAT_EXISTING_PATH`, and current `PATH`.
  # Stdout: Directory path, or an empty string when `git-lfs` cannot be located.
  # Returns: 0.
  # Notes:
  #   Used so `git lfs ...` works before prefix discovery has placed the binary on PATH.
  local _bin=""
  if [[ -n "${_RESOLVED_PREFIX:-}" && -x "${_RESOLVED_PREFIX}/bin/git-lfs" ]]; then
    printf '%s/bin\n' "${_RESOLVED_PREFIX}"
    return 0
  fi
  if [[ -n "${_FEAT_EXISTING_PATH:-}" && -x "${_FEAT_EXISTING_PATH}" ]]; then
    printf '%s\n' "${_FEAT_EXISTING_PATH%/*}"
    return 0
  fi
  _bin="$(command -v git-lfs 2> /dev/null || true)"
  [[ -n "${_bin}" ]] && printf '%s\n' "${_bin%/*}" || printf ''
}

_run_git() {
  # @brief _run_git — Run `git ...` with the feature-installed `git-lfs` available on PATH.
  #
  # Args:
  #   $1   Username to run as, or empty for the current user.
  #   $2   Repository directory for `git -C`, or empty to use the current directory.
  #   $@   Remaining arguments passed to `git`.
  # Returns: Exit status of the invoked command.
  # Notes:
  #   Git dispatches `git lfs` through PATH lookup, so this helper prepends the resolved
  #   Git LFS binary directory before invoking `git`.
  local _user="$1" _repo_dir="$2"
  shift 2
  local _bin_dir _path_env
  _bin_dir="$(_git_lfs_bin_dir)"
  _path_env="${PATH}"
  [[ -n "${_bin_dir}" ]] && _path_env="${_bin_dir}:${_path_env}"

  local -a _cmd=(env "PATH=${_path_env}" git)
  [[ -n "${_repo_dir}" ]] && _cmd+=(-C "${_repo_dir}")
  _cmd+=("$@")

  if [[ -n "${_user}" && "${_user}" != "$(users__get_current --no-sudo)" ]]; then
    users__run_as "${_user}" -- "${_cmd[@]}"
  else
    "${_cmd[@]}"
  fi
}

_repo_config_is_deferred() {
  # @brief _repo_config_is_deferred — Test whether repo-scoped config must wait for post-create.
  #
  # Args:
  #   $1  Explicit scope string.
  # Returns:
  #   0  Repo-scoped config is deferred because this is a devcontainer build with empty `repo_dir`.
  #   1  Config must be applied immediately or no repo is needed.
  local _scope="$1"
  _scope_is_repo "${_scope}" &&
    [[ -z "${REPO_DIR:-}" ]] &&
    os__is_devcontainer_build
}

_resolved_repo_dir_now() {
  # @brief _resolved_repo_dir_now — Return the repository path available in the current phase.
  #
  # Args:
  #   $1  Explicit scope string.
  # Stdout:
  #   - Empty line when no repo is needed or the repo-scoped work is intentionally deferred.
  #   - The repository path otherwise.
  # Returns:
  #   0  A usable answer was produced.
  #   1  A repository is required now but `repo_dir` is unavailable.
  local _scope="$1"
  if ! _scope_needs_repo "${_scope}"; then
    printf '\n'
    return 0
  fi
  if _repo_config_is_deferred "${_scope}"; then
    printf '\n'
    return 0
  fi
  if [[ -z "${REPO_DIR:-}" ]]; then
    logging__error "repo_dir is required for config_scope='${_scope}' when skip_repo=false or repository-scoped configuration is requested."
    return 1
  fi
  printf '%s\n' "${REPO_DIR}"
}

_assert_repo() {
  # @brief _assert_repo — Ensure the supplied path is a Git work tree.
  #
  # Args:
  #   $1  Repository directory, or empty.
  # Returns:
  #   0  Directory is empty (nothing to validate) or is a valid Git work tree.
  #   1  Directory is non-empty and not a Git work tree.
  local _repo_dir="$1"
  [[ -n "${_repo_dir}" ]] || return 0
  if ! git -C "${_repo_dir}" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    logging__error "repo_dir '${_repo_dir}' is not a Git work tree."
    return 1
  fi
}

_resolve_config_file_path() {
  # @brief _resolve_config_file_path — Resolve `config_file` against the current repo when needed.
  #
  # Args:
  #   $1  Explicit scope string.
  #   $2  Resolved repository directory, possibly empty.
  # Stdout:
  #   - Empty line for non-`file` scopes.
  #   - Absolute config path for `file` scope.
  # Returns:
  #   0  Path resolved successfully or not applicable.
  #   1  `file` scope is requested but `config_file`/repo context is insufficient.
  local _scope="$1" _repo_dir="$2"
  [[ "${_scope}" == "file" ]] || {
    printf '\n'
    return 0
  }
  if [[ -z "${CONFIG_FILE:-}" ]]; then
    logging__error "config_scope=file requires config_file."
    return 1
  fi
  if [[ "${CONFIG_FILE}" = /* ]]; then
    printf '%s\n' "${CONFIG_FILE}"
  elif [[ -n "${_repo_dir}" ]]; then
    printf '%s/%s\n' "${_repo_dir%/}" "${CONFIG_FILE}"
  else
    logging__error "Relative config_file='${CONFIG_FILE}' requires a resolved repo_dir."
    return 1
  fi
}

_enable_worktree_config() {
  # @brief _enable_worktree_config — Enable Git's `extensions.worktreeConfig` switch.
  #
  # Args:
  #   $1  Repository directory.
  #   $2  Username to run as (optional).
  # Returns: Exit status of `git config extensions.worktreeConfig true`.
  # Notes: Required before `git lfs install --worktree` or uninstalling worktree config.
  local _repo_dir="$1" _user="${2:-}"
  logging__install "Enabling extensions.worktreeConfig in '${_repo_dir}'."
  _run_git "${_user}" "${_repo_dir}" config extensions.worktreeConfig true
}

_build_install_argv() {
  # @brief _build_install_argv — Build `git lfs install` arguments for the requested config.
  #
  # Args:
  #   $1  Name of destination array variable (nameref).
  #   $2  Explicit scope string other than `none`.
  #   $3  Resolved config-file path for `file` scope, or empty.
  # Outputs:
  #   Populates the destination array with `install` plus the requested flags.
  # Returns:
  #   0  Arguments were built successfully.
  #   1  Scope is unsupported for install argument construction.
  # shellcheck disable=SC2178
  local -n _out="$1"
  local _scope="$2" _config_file="$3"
  local _manual
  _manual="$(_manual_hooks_value)"

  _out=(install)
  case "${_scope}" in
    system) _out+=(--system) ;;
    global) ;;
    local) _out+=(--local) ;;
    worktree) _out+=(--worktree) ;;
    file) _out+=("--file=${_config_file}") ;;
    *)
      logging__error "Cannot build install argv for config_scope='${_scope}'."
      return 1
      ;;
  esac
  [[ "${SKIP_REPO}" == "true" ]] && _out+=(--skip-repo)
  [[ "${SKIP_SMUDGE}" == "true" ]] && _out+=(--skip-smudge)
  [[ "${FORCE_CONFIG}" == "true" ]] && _out+=(--force)
  [[ "${_manual}" == "true" ]] && _out+=(--manual)
  return 0
}

_build_uninstall_argv_from_values() {
  # @brief _build_uninstall_argv_from_values — Build `git lfs uninstall` args from persisted values.
  #
  # Args:
  #   $1  Name of destination array variable (nameref).
  #   $2  Explicit persisted scope string other than `none`.
  #   $3  Resolved config-file path for `file` scope, or empty.
  #   $4  Persisted `skip_repo` value.
  # Outputs:
  #   Populates the destination array with `uninstall` plus the relevant flags.
  # Returns:
  #   0  Arguments were built successfully.
  #   1  Scope is unsupported for uninstall argument construction.
  # shellcheck disable=SC2178
  local -n _out="$1"
  local _scope="$2" _config_file="$3" _skip_repo="$4"

  _out=(uninstall)
  case "${_scope}" in
    system) _out+=(--system) ;;
    global) ;;
    local) _out+=(--local) ;;
    worktree) _out+=(--worktree) ;;
    file) _out+=("--file=${_config_file}") ;;
    *)
      logging__error "Cannot build uninstall argv for config_scope='${_scope}'."
      return 1
      ;;
  esac
  [[ "${_skip_repo}" == "true" ]] && _out+=(--skip-repo)
  return 0
}

_method_auto_configures_pkg_default() {
  # @brief _method_auto_configures_pkg_default — Detect package methods that bootstrap system filters.
  #
  # Args:
  #   $1  Concrete install method affecting the currently managed installation.
  # Returns:
  #   0  The method/package-manager pair is expected to provide Git LFS's default
  #      system-wide filter config automatically.
  #   1  The feature must treat filter setup as entirely feature-managed.
  # Notes:
  #   This matrix is intentionally narrow and mirrors the explicit support decision in
  #   the feature contract rather than assuming all package managers behave alike.
  local _method="$1" _pm
  _pm="$(ctx__get plat.pm)"
  case "${_method}:${_pm}" in
    package:apt | package:apk | package:dnf | package:yum | upstream-package:apt | upstream-package:dnf | upstream-package:yum)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

_pkg_default_matches_values() {
  # @brief _pkg_default_matches_values — Test whether explicit values equal the vendor default state.
  #
  # Args:
  #   $1  Scope.
  #   $2  skip_repo value.
  #   $3  skip_smudge value.
  #   $4  force_config value.
  #   $5  manual_hooks value.
  # Returns:
  #   0  Values match the package/vendor-installed default system configuration.
  #   1  Values differ from that default.
  local _scope="$1" _skip_repo="$2" _skip_smudge="$3" _force="$4" _manual="$5"
  [[ "${_scope}" == "system" ]] &&
    [[ "${_skip_repo}" == "true" ]] &&
    [[ "${_skip_smudge}" != "true" ]] &&
    [[ "${_force}" != "true" ]] &&
    [[ "${_manual}" != "true" ]]
}

_pkg_default_matches_requested() {
  # @brief _pkg_default_matches_requested — Compare the current user request to the vendor default.
  #
  # Args:
  #   $1  Explicit scope string.
  # Returns:
  #   0  Requested options match the package-installed default state.
  #   1  Requested options require explicit reconfiguration.
  local _scope="$1" _manual
  _manual="$(_manual_hooks_value)"
  _pkg_default_matches_values \
    "${_scope}" \
    "${SKIP_REPO}" \
    "${SKIP_SMUDGE}" \
    "${FORCE_CONFIG}" \
    "${_manual}"
}

_reconcile_pkg_default() {
  # @brief _reconcile_pkg_default — Remove package-installed default config before divergence.
  #
  # Args:
  #   $1  Concrete method of the installation being configured.
  #   $2  Explicit scope string.
  # Returns:
  #   0  No reconciliation was needed, or the default config was removed successfully.
  #   1  `git lfs uninstall --skip-repo --system` failed.
  # Notes:
  #   Guarded so the uninstall happens at most once per process.
  local _method="$1" _scope="$2"
  [[ -n "${_GIT_LFS_PKG_DEFAULT_RECONCILED:-}" ]] && return 0
  _method_auto_configures_pkg_default "${_method}" || return 0
  _pkg_default_matches_requested "${_scope}" && return 0

  logging__install "Removing package-installed default Git LFS system configuration before applying the requested configuration."
  local -a _argv=()
  _build_uninstall_argv_from_values _argv system "" true || return 1
  _run_git "" "" lfs "${_argv[@]}"
  declare -g _GIT_LFS_PKG_DEFAULT_RECONCILED=1
}

_apply_current_non_global_config() {
  # @brief _apply_current_non_global_config — Apply or defer non-global Git LFS configuration.
  #
  # Args:
  #   $1  Explicit scope string (`system`, `local`, `worktree`, or `file`).
  #   $2  Concrete method of the installation being configured.
  # Returns:
  #   0  Configuration was applied, intentionally skipped, or deferred successfully.
  #   1  Validation, reconciliation, or `git lfs install` failed.
  # Notes:
  #   - Repository-scoped config may be deferred until post-create when `repo_dir` is
  #     unavailable during devcontainer image build.
  #   - Package-installed system defaults are preserved when they already match.
  local _scope="$1" _method="$2"
  # Git LFS configuration registers LFS filters in git's config, so it needs
  # git. Normally the base run dependencies install it, but a non-root install
  # (no privilege to install packages) or an if_exists=skip over a prior binary
  # may run with git absent. Skip configuration with a warning rather than
  # failing the whole install — the git-lfs binary is still usable once git is
  # present.
  if ! command -v git > /dev/null 2>&1; then
    logging__warn "git is not on PATH; skipping Git LFS '${_scope}' configuration (install git, then re-run to configure LFS)."
    return 0
  fi
  if _repo_config_is_deferred "${_scope}"; then
    logging__info "Deferring repo-scoped Git LFS configuration to postCreateCommand because repo_dir is empty during the devcontainer build."
    return 0
  fi

  local _repo_dir _config_file
  _repo_dir="$(_resolved_repo_dir_now "${_scope}")" || return 1
  _assert_repo "${_repo_dir}" || return 1
  _config_file="$(_resolve_config_file_path "${_scope}" "${_repo_dir}")" || return 1

  if [[ "${_scope}" == "worktree" ]]; then
    _enable_worktree_config "${_repo_dir}"
  fi

  if _method_auto_configures_pkg_default "${_method}" &&
    _pkg_default_matches_requested "${_scope}"; then
    logging__info "Package installation already provides the requested Git LFS system defaults; skipping explicit git lfs install."
    return 0
  fi

  _reconcile_pkg_default "${_method}" "${_scope}" || return 1

  local -a _argv=()
  _build_install_argv _argv "${_scope}" "${_config_file}" || return 1
  logging__install "Applying Git LFS configuration at scope='${_scope}'."
  _run_git "" "${_repo_dir}" lfs "${_argv[@]}"
}

_write_state() {
  # @brief _write_state — Persist the feature-managed Git LFS configuration contract.
  #
  # Args:
  #   $1  Explicit resolved scope.
  #   $2  Concrete method of the installation being configured.
  # Side effects:
  #   - Writes `${_FEAT_SHARE_DIR_ROOT}/state/config.env`.
  #   - Writes/clears `${_FEAT_SHARE_DIR_ROOT}/state/global-users`.
  # Returns: 0.
  # Notes: The post-create hook and uninstall path both consume this state.
  local _scope="$1" _method="$2"
  local _state_dir _state_file _users_file
  _state_dir="$(_state_dir)"
  _state_file="$(_state_env_file)"
  _users_file="$(_global_users_file)"

  file__mkdir "${_state_dir}"
  {
    _emit_state_var GIT_LFS_STATE_ACTIVE_METHOD "${_method}"
    _emit_state_var GIT_LFS_STATE_CONFIG_SCOPE "${_scope}"
    _emit_state_var GIT_LFS_STATE_CONFIG_FILE "${CONFIG_FILE:-}"
    _emit_state_var GIT_LFS_STATE_REPO_DIR "${REPO_DIR:-}"
    _emit_state_var GIT_LFS_STATE_SKIP_REPO "${SKIP_REPO}"
    _emit_state_var GIT_LFS_STATE_SKIP_SMUDGE "${SKIP_SMUDGE}"
    _emit_state_var GIT_LFS_STATE_FORCE_CONFIG "${FORCE_CONFIG}"
    _emit_state_var GIT_LFS_STATE_MANUAL_HOOKS "$(_manual_hooks_value)"
    _emit_state_var GIT_LFS_STATE_AUTO_PULL "${AUTO_PULL}"
  } | file__tee "${_state_file}"

  if [[ "${_scope}" == "global" && -v _FEAT_CONFIGURE_USERS ]]; then
    if ((${#_FEAT_CONFIGURE_USERS[@]} > 0)); then
      printf '%s\n' "${_FEAT_CONFIGURE_USERS[@]}" | file__tee "${_users_file}"
    else
      printf '' | file__tee "${_users_file}"
    fi
  else
    file__rm -f "${_users_file}" 2> /dev/null || true
  fi
}

_finalize_config_state() {
  # @brief _finalize_config_state — Apply feature-managed config and persist the result.
  #
  # Args: none; reads the current option set plus resolved configure-users results.
  # Returns:
  #   0  Config/state finalization completed successfully.
  #   1  Scope resolution, config application, or state persistence failed.
  # Notes:
  #   Called from both install-finish and skip flows after any per-user configuration work.
  local _scope _method
  _scope="$(_resolved_scope)" || return 1
  _method="$(_effective_method)" || return 1

  if [[ "${_scope}" == "none" ]]; then
    logging__info "config_scope=none; skipping feature-managed Git LFS configuration."
  elif [[ "${_scope}" == "global" ]]; then
    if [[ -n "${_GIT_LFS_CONFIGURE_USER_FAILED:-}" ]]; then
      logging__error "One or more global Git LFS user-configuration steps failed."
      return 1
    fi
    if [[ ! -v _FEAT_CONFIGURE_USERS || ${#_FEAT_CONFIGURE_USERS[@]} -eq 0 ]]; then
      _reconcile_pkg_default "${_method}" "${_scope}" || return 1
      logging__skip "No users resolved for global Git LFS configuration."
    fi
  else
    _apply_current_non_global_config "${_scope}" "${_method}" || return 1
  fi

  _write_state "${_scope}" "${_method}"
}

__configure_user() {
  # @brief __configure_user — Apply Git LFS global configuration for one resolved user.
  #
  # Args:
  #   $1  Username selected by the template's configure-users machinery.
  # Returns:
  #   0  User configuration succeeded or did not apply to the current scope.
  #   1  Resolution/reconciliation/install failed for that user.
  # Side effects:
  #   Sets `_GIT_LFS_CONFIGURE_USER_FAILED=1` on failure so `_finalize_config_state`
  #   can fail the overall install/skip lifecycle.
  # Notes:
  #   Only `config_scope=global` is handled here; all other scopes are managed elsewhere.
  local _user="$1"
  # See _apply_current_non_global_config: Git LFS config needs git; skip
  # gracefully when it is absent (e.g. a non-root install with no privilege to
  # install the git run dependency) rather than failing the install.
  if ! command -v git > /dev/null 2>&1; then
    logging__warn "git is not on PATH; skipping Git LFS configuration for user '${_user}'."
    return 0
  fi
  local _scope _method _repo_dir _config_file
  _scope="$(_resolved_scope)" || {
    declare -g _GIT_LFS_CONFIGURE_USER_FAILED=1
    return 1
  }
  [[ "${_scope}" == "global" ]] || return 0

  _method="$(_effective_method)" || {
    declare -g _GIT_LFS_CONFIGURE_USER_FAILED=1
    return 1
  }
  _repo_dir="$(_resolved_repo_dir_now "${_scope}")" || {
    declare -g _GIT_LFS_CONFIGURE_USER_FAILED=1
    return 1
  }
  _assert_repo "${_repo_dir}" || {
    declare -g _GIT_LFS_CONFIGURE_USER_FAILED=1
    return 1
  }
  _config_file="$(_resolve_config_file_path "${_scope}" "${_repo_dir}")" || {
    declare -g _GIT_LFS_CONFIGURE_USER_FAILED=1
    return 1
  }

  _reconcile_pkg_default "${_method}" "${_scope}" || {
    declare -g _GIT_LFS_CONFIGURE_USER_FAILED=1
    return 1
  }

  local -a _argv=()
  _build_install_argv _argv "${_scope}" "${_config_file}" || {
    declare -g _GIT_LFS_CONFIGURE_USER_FAILED=1
    return 1
  }

  logging__install "Applying Git LFS global configuration for user '${_user}'."
  _run_git "${_user}" "${_repo_dir}" lfs "${_argv[@]}" || {
    declare -g _GIT_LFS_CONFIGURE_USER_FAILED=1
    return 1
  }
}

__install_finish_post() {
  # @brief __install_finish_post — Finalize Git LFS config after template-owned install work.
  #
  # Args: none.
  # Returns: Same status as `_finalize_config_state`.
  _finalize_config_state
}

__skip_post() {
  # @brief __skip_post — Refresh state/lifecycle artifacts when installation is skipped.
  #
  # Args: none.
  # Returns:
  #   0  Validation, config finalization, and lifecycle redeploy succeeded.
  #   1  Validation or config finalization failed.
  # Notes:
  #   The template has already deployed lifecycle scripts with `_SKIP=1` before this hook.
  #   This hook rewrites the real state contract and redeploys the lifecycle scripts without
  #   `--skip` so post-create sees the current Git LFS configuration request.
  _validate_requested_config || return 1
  _finalize_config_state || return 1
  __deploy_lifecycle_scripts__
}

_uninstall_state_for_user() {
  # @brief _uninstall_state_for_user — Remove one persisted Git LFS config instance.
  #
  # Args:
  #   $1  Username for global-scope uninstall, or empty otherwise.
  #   $2  Persisted scope.
  #   $3  Resolved config-file path for `file` scope, or empty.
  #   $4  Repository directory, or empty.
  #   $5  Persisted `skip_repo` value.
  # Returns: Exit status of the `git lfs uninstall` command.
  # Notes: Enables `extensions.worktreeConfig` first when uninstalling worktree-scoped config.
  local _user="$1" _scope="$2" _config_file="$3" _repo_dir="$4" _skip_repo="$5"
  local -a _argv=()
  local _log_message
  if [[ "${_scope}" == "worktree" && -n "${_repo_dir}" ]]; then
    _enable_worktree_config "${_repo_dir}" "${_user}" || return 1
  fi
  _build_uninstall_argv_from_values _argv "${_scope}" "${_config_file}" "${_skip_repo}" || return 1
  _log_message="Removing Git LFS configuration at scope='${_scope}'."
  if [[ -n "${_user}" ]]; then
    _log_message="Removing Git LFS configuration at scope='${_scope}' for user '${_user}'."
  fi
  logging__remove "${_log_message}"
  _run_git "${_user}" "${_repo_dir}" lfs "${_argv[@]}"
}

_uninstall_managed_config() {
  # @brief _uninstall_managed_config — Replay persisted state to remove feature-owned config.
  #
  # Args: none; reads the persisted state files written by `_write_state`.
  # Returns:
  #   0  Managed uninstall completed, was intentionally skipped, or nothing was recorded.
  #   1  A required uninstall step failed.
  # Notes:
  #   - Skips explicit uninstall when package removal is expected to remove the exact
  #     vendor-default system config.
  #   - Global uninstall iterates the stored user list captured at install/skip time.
  local _state_file _users_file
  _state_file="$(_state_env_file)"
  _users_file="$(_global_users_file)"
  [[ -f "${_state_file}" ]] || return 0

  # shellcheck disable=SC1090
  . "${_state_file}"

  local _scope="${GIT_LFS_STATE_CONFIG_SCOPE:-none}"
  local _method="${GIT_LFS_STATE_ACTIVE_METHOD:-}"
  local _repo_dir="${GIT_LFS_STATE_REPO_DIR:-}"
  local _config_file="${GIT_LFS_STATE_CONFIG_FILE:-}"
  local _skip_repo="${GIT_LFS_STATE_SKIP_REPO:-true}"
  local _skip_smudge="${GIT_LFS_STATE_SKIP_SMUDGE:-false}"
  local _force="${GIT_LFS_STATE_FORCE_CONFIG:-false}"
  local _manual="${GIT_LFS_STATE_MANUAL_HOOKS:-false}"

  [[ -n "${_scope}" && "${_scope}" != "none" ]] || return 0

  if _method_auto_configures_pkg_default "${_method}" &&
    _pkg_default_matches_values "${_scope}" "${_skip_repo}" "${_skip_smudge}" "${_force}" "${_manual}"; then
    logging__skip "Package uninstall will remove the default Git LFS system configuration; skipping explicit feature-managed uninstall."
    return 0
  fi

  if [[ "${_scope}" == "global" ]]; then
    [[ -f "${_users_file}" ]] || {
      logging__skip "No stored global-users file found; skipping Git LFS global uninstall."
      return 0
    }
    local _user
    while IFS= read -r _user; do
      [[ -n "${_user}" ]] || continue
      if ! id "${_user}" > /dev/null 2>&1; then
        logging__warn "Stored user '${_user}' no longer exists; skipping Git LFS global uninstall for that user."
        continue
      fi
      _uninstall_state_for_user "${_user}" "${_scope}" "" "${_repo_dir}" "${_skip_repo}" || return 1
    done < "${_users_file}"
    return 0
  fi

  if { _scope_is_repo "${_scope}" || [[ "${_skip_repo}" == "false" ]]; } && [[ -z "${_repo_dir}" ]]; then
    logging__warn "Stored repo_dir is empty; skipping repo-scoped Git LFS uninstall."
    return 0
  fi
  if [[ -n "${_repo_dir}" ]] && ! git -C "${_repo_dir}" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    logging__warn "Stored repo_dir '${_repo_dir}' is no longer a Git work tree; skipping repo-scoped Git LFS uninstall."
    return 0
  fi

  if [[ "${_scope}" == "file" && "${_config_file}" != /* ]]; then
    if [[ -z "${_repo_dir}" ]]; then
      logging__warn "Stored relative config_file='${_config_file}' has no repo_dir context; skipping file-scoped Git LFS uninstall."
      return 0
    fi
    _config_file="${_repo_dir%/}/${_config_file}"
  fi

  _uninstall_state_for_user "" "${_scope}" "${_config_file}" "${_repo_dir}" "${_skip_repo}"
}

__uninstall_run_pre() {
  # @brief __uninstall_run_pre — Remove feature-managed Git LFS config before tool uninstall.
  #
  # Args: none.
  # Returns: Same status as `_uninstall_managed_config`.
  _uninstall_managed_config
}

__uninstall_finish_post() {
  # @brief __uninstall_finish_post — Remove feature-owned persistent state after uninstall.
  #
  # Args: none.
  # Side effects:
  #   Deletes the config env file, global-users file, installed-method file, and then tries
  #   to remove now-empty feature share directories.
  # Returns: 0.
  # Notes:
  #   The template already attempted some directory cleanup before calling this hook, so this
  #   hook performs a second explicit cleanup for the state paths created by this feature.
  local _state_dir _state_file _users_file _installed_method
  _state_dir="$(_state_dir)"
  _state_file="$(_state_env_file)"
  _users_file="$(_global_users_file)"
  _installed_method="${_state_dir}/installed-method"

  file__rm -f "${_state_file}" 2> /dev/null || true
  file__rm -f "${_users_file}" 2> /dev/null || true
  file__rm -f "${_installed_method}" 2> /dev/null || true
  file__rm -d "${_state_dir}" 2> /dev/null || true
  file__rm -d "${_FEAT_SHARE_DIR_ROOT}" 2> /dev/null || true
  file__rm -d "${_FEAT_SHARE_DIR_NONROOT}" 2> /dev/null || true
}
