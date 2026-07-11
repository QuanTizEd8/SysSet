#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s inherit_errexit

__print_docs__() {
  cat << 'EOF'
${{ name }}$ v${{ version }}$

Usage: install.bash [OPTIONS]

Options:
${{ _script.usage_options }}$
EOF
  return
}

__run_feature_hook__() {
  # Execute a feature hook if defined, with debug logging.
  # On failure, exits the script (to avoid double-logging via the ERR trap).
  # Pass --warn to log a warning instead and return 0 (non-fatal callers).
  local _rh_warn=""
  if [[ "${1:-}" == --warn ]]; then
    _rh_warn=1
    shift
  fi
  local _hook="$1"
  shift
  if declare -f "${_hook}" > /dev/null; then
    logging__debug "Executing feature hook '${_hook}'."
    "${_hook}" "$@"
    local _rc=$?
    if [[ $_rc == 0 ]]; then
      logging__debug "Feature hook '${_hook}' executed successfully."
    elif [[ -n "${_rh_warn}" ]]; then
      logging__warn "Feature hook '${_hook}' failed (non-fatal)."
    else
      logging__error "Feature hook '${_hook}' failed."
      exit "$_rc"
    fi
  else
    logging__debug "No feature hook '${_hook}' found. Skipping."
  fi
}

__main__() {
  # Main entry point for the install script.

  trap '__exit__' EXIT
  trap '__err__' ERR
  __init__ "$@"

  if [[ ! -v IF_EXISTS ]]; then
    logging__info "if_exists unset; installing directly without existence checks."
    __install__
    logging__info "Install finished (if_exists unset); exiting."
    exit 0
  fi

  __resolve_input_prefixes__
  logging__info "Checking for existing installation"
  __detect_existing__

  __if_exists_dispatch__
}

__if_exists_dispatch__() {
  if [[ "${_FEAT_EXISTING}" != true ]]; then
    case "${IF_EXISTS}" in
      uninstall)
        logging__info "'${_FEAT_CONTRACT_PRIMARY_BIN:-tool}' not found; nothing to uninstall (if_exists=uninstall)."
        logging__info "Exiting with status 0."
        exit 0
        ;;
      *)
        logging__info "'${_FEAT_CONTRACT_PRIMARY_BIN:-tool}' not found; installing (if_exists=${IF_EXISTS})."
        __install__
        logging__info "Install lifecycle finished; exiting with status 0."
        exit 0
        ;;
    esac
  else
    case "${IF_EXISTS}" in
      skip)
        logging__info "'${_FEAT_CONTRACT_PRIMARY_BIN:-tool}' already present at '${_FEAT_EXISTING_PATH}'; skipping (if_exists=skip)."
        __deploy_lifecycle_scripts__ --skip
        ${{ _script.configure_users_call }}$
        __run_feature_hook__ __skip_post
        logging__info "Skip lifecycle finished; exiting with status 0."
        exit 0
        ;;
      fail)
        logging__error "'${_FEAT_CONTRACT_PRIMARY_BIN:-tool}' already present at '${_FEAT_EXISTING_PATH}'; failing (if_exists=fail)."
        logging__fatal "Exiting with status 1 (if_exists=fail)."
        exit 1
        ;;
      uninstall)
        logging__info "'${_FEAT_CONTRACT_PRIMARY_BIN:-tool}' already present at '${_FEAT_EXISTING_PATH}'; uninstalling (if_exists=uninstall)."
        __uninstall__
        logging__info "Uninstall lifecycle finished; exiting with status 0."
        exit 0
        ;;
      reinstall)
        logging__info "'${_FEAT_CONTRACT_PRIMARY_BIN:-tool}' already present at '${_FEAT_EXISTING_PATH}'; reinstalling (if_exists=reinstall)."
        __reinstall__
        logging__info "Reinstall lifecycle finished; exiting with status 0."
        exit 0
        ;;
      update)
        logging__info "'${_FEAT_CONTRACT_PRIMARY_BIN:-tool}' already present at '${_FEAT_EXISTING_PATH}'; updating (if_exists=update)."
        __update__
        logging__info "Update lifecycle finished; exiting with status 0."
        exit 0
        ;;
      *)
        logging__error "Unknown if_exists value: '${IF_EXISTS}'"
        logging__fatal "Exiting with status 1 (unknown if_exists)."
        exit 1
        ;;
    esac
  fi
}

# Initialization
# ==============
__init__() {
  # Initialize the script.

  if declare -f __init_pre > /dev/null; then
    __init_pre
  fi

  __init_env__
  __init_lib__
  logging__feature_entry "$_FEAT_NAME v$_FEAT_VERSION"
  file__session_ensure

  if [[ -n "${_BASH_INSTALLED_INTERNALLY:-}" ]] && [[ -n "${_BASH_BIN:-}" ]]; then
    install__track_internal_path "bash-bootstrap" "${_BASH_BIN}"
  fi
  unset _BASH_INSTALLED_INTERNALLY
  export -n _BASH_INSTALLED_BY_PM   # keep value in this process, don't leak to children
  export -n _BASH_BIN               # same: _BASH_BIN stays accessible for shell__bash()

  __init_args__ "$@"
  __init_script__

  __run_feature_hook__ __init_post
}

__init_env__() {
  # Set internal environment variables.

  if declare -f __init_env_pre > /dev/null; then
    __init_env_pre
  fi

  # Runtime-computed variables (not in metadata; depend on script location):
  _FEAT_DIR="$(cd "$(dirname "$0")" && pwd)"
  _FEAT_FILES_DIR="${_FEAT_DIR}/files"

  # Metadata-derived variables (canonical source: metadata.shared.yaml _env_vars):
  ${{ _script.env_vars.assignments }}$

  # Contract variables (derived from _options.version and _options.method in metadata.yaml):
  ${{ _script.install_contract_vars.assignments }}$

  # Lifecycle conf-vars map (generated from metadata _conf_vars declarations):
  declare -gA _FEAT_LIFECYCLE_CONF_VARS=(${{ _script.lifecycle_conf_vars }}$)

  # Unexport variables — values remain accessible in this script,
  # but are not inherited by child processes.
  declare -g +x _FEAT_DIR _FEAT_FILES_DIR \
    ${{ _script.env_vars.unexports }}$ \
    ${{ _script.install_contract_vars.unexports }}$ \
    _FEAT_LIFECYCLE_CONF_VARS

  _SYSSET_BUILD_CONTEXT="${_SYSSET_BUILD_CONTEXT:-feature::$_FEAT_ID}"
  export _SYSSET_BUILD_CONTEXT

  if declare -f __init_env_post > /dev/null; then
    __init_env_post
  fi
}

__init_lib__() {
  # Source library functions.

  if declare -f __init_lib_pre > /dev/null; then
    __init_lib_pre
  fi

  # shellcheck source=lib/__init__.bash
  . "$_FEAT_DIR/lib/__init__.bash"

  if declare -f __init_lib_post > /dev/null; then
    __init_lib_post
  fi
}

__init_script__() {
  # Set up logging and exit trap.

  __run_feature_hook__ __init_script_pre

  logging__setup --prefix "${_FEAT_ID}" --fn-prefix

  __run_feature_hook__ __init_script_post
}

__init_args__() {
  # Parse and validate input arguments and apply defaults.

  __run_feature_hook__ __init_args_pre "$@"

  if [ "$#" -gt 0 ]; then
    ${{ _script.argparse.cli_inits }}$

    logging__info "Script called with arguments: $*"

    while [ "$#" -gt 0 ]; do
      case $1 in
        ${{ _script.argparse.case_arms }}$
        -h | --help)
          logging__info "Showing help (--help); exiting."
          __print_docs__
          exit 0
          ;;
        --*)
          logging__error "Unknown option: '${1}'"
          logging__fatal "Exiting with status 1 (unknown option)."
          exit 1
          ;;
        *)
          logging__error "Unexpected argument: '${1}'"
          logging__fatal "Exiting with status 1 (unexpected argument)."
          exit 1
          ;;
      esac
    done
  else
    ${{ _script.argparse.env_reads }}$

    logging__info "Script called with no arguments. Read environment variables."
  fi

  # Apply defaults.
  ${{ _script.argparse.defaults }}$

  # Normalize array options (trim elements; drop blank/whitespace-only lines).
  ${{ _script.argparse.normalize_arrays }}$

  # Resolve URI-capable option values to local filesystem paths (INSTALLER_DIR or a private temp dir).
  ${{ _script.argparse.uri_resolution }}$

  # Resolve file-content-or-URI options (inline content, remote URIs, or local paths) to local paths.
  ${{ _script.argparse.content_or_uri_resolution }}$

  # Option-bound dependency trigger specs (consumed by __dep_install_option_bound__).
  ${{ _script.dep_trigger_specs }}$

  # Validate input options.
  ${{ _script.argparse.validations }}$

  # Validate option values against their JSON Schemas.
  ${{ _script.argparse.jsonschema_validations }}$

  # Unexport option variables — values remain accessible in this script,
  # but are not inherited by child processes.
  declare -g +x ${{ _script.argparse.unexports }}$

  __run_feature_hook__ __init_args_post
  __feat_capture_version_input__
  __ctx_sync__
}

# Existing installation detection
# ===============================
__detect_existing__() {

  __run_feature_hook__ __detect_existing_pre

  # Existence detection (cheap; side-effect-free)
  __detect_existing_path__
  # Existing installation method detection (no-op when nothing found)
  __detect_existing_method__

  logging__detect "Detection complete: path='${_FEAT_EXISTING_PATH:-}', method='${_FEAT_EXISTING_METHOD:-}'."

  __run_feature_hook__ __detect_existing_post
}

__detect_existing_path__() {
  # Answer "is the tool already installed?" and record the result in
  # _FEAT_EXISTING_PATH (empty string = not found).
  #
  # Searches three locations in order, stopping as soon as one yields a hit:
  #  1. The feature's configured prefix directory — a binary installed there may
  #     be absent from PATH when the shell profile has not been sourced yet, which
  #     is common in fresh container builds where dotfiles are not yet loaded.
  #  2. RUNTIME_PATH (the user's PATH at container runtime, after all profiles are
  #     sourced) — tried when the feature exposes a RUNTIME_PATH option, because
  #     the runtime PATH may include directories not present at install time (e.g.
  #     ~/.local/bin added by a previously installed tool's profile snippet).
  #  3. The install-time PATH via 'command -v' — always tried as a final fallback
  #     when the prefix and RUNTIME_PATH checks both come up empty, to catch
  #     system-wide installs that bypass this feature's prefix entirely.
  #
  # Use __detect_existing_path_pre to set _FEAT_EXISTING_PATH before the auto-impl
  # runs, or override __detect_existing_path__ entirely when the tool's presence
  # cannot be determined by looking for a single binary (e.g. shell function,
  # directory, non-standard layout).
  #
  # If no primary binary name is known, _FEAT_EXISTING_PATH stays "". The
  # early-exit logic then treats the tool as absent and proceeds with a fresh
  # install regardless of if_exists.

  __run_feature_hook__ __detect_existing_path_pre

  declare -g _FEAT_EXISTING_PATH=""
  declare -g _FEAT_EXISTING=false

  # git-clone: check PREFIX first — for git-clone features, PREFIX IS the installation root.
  # Probing this before the binary search prevents a git-clone feature that also exposes a
  # primary binary from being misclassified as a plain "prefix" (binary) installation.
  if argparse__var_declared PREFIX \
    && [[ -n "${GIT_CLONE_URI:-}" && -v _RESOLVED_PREFIX && -d "${_RESOLVED_PREFIX}/.git" ]]; then
    _FEAT_EXISTING_PATH="${_RESOLVED_PREFIX}"
    logging__detect "Found git-clone repository at '${_FEAT_EXISTING_PATH}'."
  fi

  # Binary detection only when not already found by the git-clone check.
  if [[ -z "${_FEAT_EXISTING_PATH}" && -n "${_FEAT_CONTRACT_PRIMARY_BIN:-}" ]]; then
    local _prefix_bin=""
    if argparse__var_declared PREFIX; then
      _prefix_bin="${_RESOLVED_PREFIX}/bin/${_FEAT_CONTRACT_PRIMARY_BIN}"
    fi
    if [[ -n "${_prefix_bin}" && -x "${_prefix_bin}" ]]; then
      _FEAT_EXISTING_PATH="${_prefix_bin}"
      logging__detect "Found '${_FEAT_CONTRACT_PRIMARY_BIN}' in prefix at '${_FEAT_EXISTING_PATH}'."
    else
      if [[ -v _RESOLVED_RUNTIME_PATH ]]; then
        _FEAT_EXISTING_PATH="$(PATH="${_RESOLVED_RUNTIME_PATH}" command -v "${_FEAT_CONTRACT_PRIMARY_BIN}" 2>/dev/null || true)"
        [[ -n "${_FEAT_EXISTING_PATH}" ]] && \
          logging__detect "Found '${_FEAT_CONTRACT_PRIMARY_BIN}' on RUNTIME_PATH at '${_FEAT_EXISTING_PATH}'."
      fi
      if [[ -z "${_FEAT_EXISTING_PATH}" ]]; then
        _FEAT_EXISTING_PATH="$(command -v "${_FEAT_CONTRACT_PRIMARY_BIN}" 2>/dev/null || true)"
        [[ -n "${_FEAT_EXISTING_PATH}" ]] && \
          logging__detect "Found '${_FEAT_CONTRACT_PRIMARY_BIN}' on install-time PATH at '${_FEAT_EXISTING_PATH}'."
      fi
    fi
  elif [[ -z "${_FEAT_EXISTING_PATH}" && -z "${_FEAT_CONTRACT_PRIMARY_BIN:-}" ]]; then
    logging__skip "No primary binary configured; skipping binary existence probe."
  fi

  if [[ -z "${_FEAT_EXISTING_PATH}" && -n "${_FEAT_CONTRACT_PRIMARY_BIN:-}" ]]; then
    logging__detect "No existing '${_FEAT_CONTRACT_PRIMARY_BIN}' installation found."
  fi

  __run_feature_hook__ __detect_existing_path_post
  # Derive _FEAT_EXISTING from path if a hook hasn't already set it to true.
  if [[ -n "${_FEAT_EXISTING_PATH}" ]]; then _FEAT_EXISTING=true; fi
}

__detect_existing_method__() {
  # Determine how the existing installation (recorded in _FEAT_EXISTING_PATH) was
  # installed, and record the result in _FEAT_EXISTING_METHOD. Called as step 1b
  # immediately after __detect_existing_path__; no-op when _FEAT_EXISTING_PATH is
  # empty (nothing installed).
  #
  # Auto-implementation probe order (stops at first match):
  #  1. ospkg__is_managed: the OS package manager owns _FEAT_EXISTING_PATH.
  #     → "package"
  #  2. npm__is_bundled: the binary lives inside an npm package directory.
  #     → "npm-bundled"
  #  3. npm__is_managed: the npm global registry lists NPM_PACKAGE.
  #     Only tried when NPM_PACKAGE is non-empty.
  #     → "npm"
  #  4. Prefix path: _FEAT_EXISTING_PATH is under the feature's configured prefix.
  #     → "prefix" (exact sub-method — binary, cargo, source, script — is not
  #       distinguished; __uninstall__ removes the binary and any
  #       declared sidecar, which is sufficient for most tools).
  #  5. No match → "" (unknown; override __uninstall_run__ to handle custom
  #     teardown, or use __uninstall_run_pre to set _FEAT_EXISTING_METHOD).
  #
  # Use __detect_existing_method_pre to set _FEAT_EXISTING_METHOD before the
  # auto-impl runs, or override __detect_existing_method__ for fully custom logic.

  __run_feature_hook__ __detect_existing_method_pre

  declare -g _FEAT_EXISTING_METHOD=""
  if [[ "${_FEAT_EXISTING}" != true ]]; then
    logging__skip "No existing installation; skipping method detection."
    return 0
  fi
  if [[ -z "${_FEAT_EXISTING_PATH}" ]]; then
    logging__skip "Existing flag set but no path available; skipping method detection."
    return 0
  fi

  # git-clone: probe first so that a git-clone feature is never misclassified as "prefix".
  # _FEAT_EXISTING_PATH for git-clone features is always PREFIX (set by __detect_existing_path__),
  # which is a directory — ospkg/npm probes against a directory path always return false, but
  # the prefix check (PATH == PREFIX/*) would also not match (PATH == PREFIX, not PREFIX/something).
  # Placing this first is both correct and defensive against future git-clone features that also
  # expose a primary binary whose path would match the prefix check.
  if [[ -n "${GIT_CLONE_URI:-}" && -d "${_FEAT_EXISTING_PATH}/.git" ]]; then
    _FEAT_EXISTING_METHOD="git-clone"
  elif ospkg__is_managed "${_FEAT_EXISTING_PATH}" 2>/dev/null; then
    local _method_state_base="${_FEAT_SHARE_DIR_ROOT}"
    users__is_user_path "${_FEAT_EXISTING_PATH}" && _method_state_base="${_FEAT_SHARE_DIR_NONROOT}"
    local _method_state="${_method_state_base}/state/installed-method"
    if [[ -f "${_method_state}" ]]; then
      _FEAT_EXISTING_METHOD="$(< "${_method_state}")"
    else
      _FEAT_EXISTING_METHOD="package"
    fi
  elif npm__is_bundled "${_FEAT_EXISTING_PATH}" 2>/dev/null; then
    _FEAT_EXISTING_METHOD="npm-bundled"
  elif [[ -n "${NPM_PACKAGE:-}" ]] \
    && npm__is_managed "${_FEAT_EXISTING_PATH}" 2>/dev/null; then
    _FEAT_EXISTING_METHOD="npm"
  elif argparse__var_declared PREFIX; then
    local _prefix_val="${_RESOLVED_PREFIX:-}"
    if [[ -n "${_prefix_val}" && "${_FEAT_EXISTING_PATH}" == "${_prefix_val}/"* ]]; then
      _FEAT_EXISTING_METHOD="prefix"
    fi
  fi

  if [[ -n "${_FEAT_EXISTING_METHOD}" ]]; then
    logging__detect "Detected installation method '${_FEAT_EXISTING_METHOD}' for '${_FEAT_EXISTING_PATH}'."
  else
    logging__warn "Could not determine installation method for '${_FEAT_EXISTING_PATH}'."
  fi

  __run_feature_hook__ __detect_existing_method_post
}

# Uninstallation
# ===============
__uninstall__() {

  logging__info "Starting uninstall (path='${_FEAT_EXISTING_PATH:-}', method='${_FEAT_EXISTING_METHOD:-}')."

  __run_feature_hook__ __uninstall_pre

  __uninstall_init__
  __uninstall_run__
  __uninstall_finish__

  __run_feature_hook__ __uninstall_post
}

__uninstall_init__() {
  logging__debug "Starting uninstall initialization."

  __run_feature_hook__ __uninstall_init_pre

  __verify_system_requirements__
  __resolve_input_method__
  __resolve_input_prefixes__

  __run_feature_hook__ __uninstall_init_post
}

__uninstall_run__() {
  # Uninstall the existing installation recorded in _FEAT_EXISTING_PATH, using
  # the method detected by __detect_existing_method__ (step 1b).
  #
  # Called in three contexts:
  #   Step 2:                     if_exists=uninstall
  #   __reinstall__: if_exists=reinstall (existing path non-empty)
  #   __update__:    method migration during update
  #
  # Requires __detect_existing_path__ (step 1) and __detect_existing_method__
  # (step 1b) to have already run.
  #
  # Auto-implementations (keyed by _FEAT_EXISTING_METHOD):
  #   prefix            file__rm the primary binary (_FEAT_EXISTING_PATH) and any sidecar
  #                     declared in BINARY_SIDECAR_URI. Suitable for binary, cargo,
  #                     and simple source/script installs.
  #   npm               npm__uninstall_package for NPM_PACKAGE.
  #   npm-bundled       npm__uninstall_bundled --bin _FEAT_EXISTING_PATH.
  #   package           ospkg__run --manifest from OSPKG_MANIFEST_METHOD_PACKAGE_RUN --remove.
  #   upstream-package  ospkg__run --manifest from OSPKG_MANIFEST_METHOD_UPSTREAM_PACKAGE_RUN --remove.
  #   ""                No auto-impl — method unknown.
  #
  # For custom teardown (config files, extra binaries, etc.), use
  # __uninstall_run_pre to act before the auto-impl, or override __uninstall_run__
  # entirely when you need to replace it.

  __run_feature_hook__ __uninstall_run_pre

  logging__remove "Uninstalling via method='${_FEAT_EXISTING_METHOD:-unknown}' from '${_FEAT_EXISTING_PATH}'."

  case "${_FEAT_EXISTING_METHOD:-}" in
    prefix)
      __uninstall_run_prefix__
      ;;
    npm)
      __uninstall_run_npm__
      ;;
    npm-bundled)
      __uninstall_run_npm_bundled__
      ;;
    package)
      __uninstall_run_package__
      ;;
    upstream-package)
      __uninstall_run_upstream_package__
      ;;
    git-clone)
      __uninstall_run_git_clone__
      ;;
    "")
      logging__error "Cannot auto-uninstall '${_FEAT_EXISTING_PATH}': installation method unknown. Override __uninstall_run__ or use __uninstall_run_pre to handle it."
      return 1
      ;;
    *)
      logging__error "Cannot auto-uninstall '${_FEAT_EXISTING_PATH}': unrecognized _FEAT_EXISTING_METHOD='${_FEAT_EXISTING_METHOD}'. Override __uninstall_run__ or use __uninstall_run_pre to handle it."
      return 1
      ;;
  esac

  logging__info "Uninstall run finished for method='${_FEAT_EXISTING_METHOD:-}'."

  __run_feature_hook__ __uninstall_run_post
}

__uninstall_run_prefix__() {
  __run_feature_hook__ __uninstall_run_prefix_pre
  local _bin_dir="${_FEAT_EXISTING_PATH%/*}"
  if argparse__var_declared BINARY_SRC && [[ ${#BINARY_SRC[@]} -gt 0 ]]; then
    local _src
    local -a _active_src=()
    mapfile -t _active_src < <(__feat_filter_binary_src__)
    for _src in "${_active_src[@]+"${_active_src[@]}"}"; do
      [[ -n "${_src}" ]] || continue
      logging__remove "Removing binary '${_bin_dir}/${_src##*/}'."
      file__rm -f "${_bin_dir}/${_src##*/}" 2>/dev/null || true
    done
  else
    logging__remove "Removing prefix binary '${_FEAT_EXISTING_PATH}'."
    file__rm -f "${_FEAT_EXISTING_PATH}"
  fi
  if argparse__var_declared SOURCE_INSTALL_BINS && [[ ${#SOURCE_INSTALL_BINS[@]} -gt 0 ]]; then
    local _src_bin
    local -a _active_source_bins=()
    mapfile -t _active_source_bins < <(__feat_filter_source_install_bins__)
    for _src_bin in "${_active_source_bins[@]+"${_active_source_bins[@]}"}"; do
      [[ -n "${_src_bin}" ]] || continue
      logging__remove "Removing source-installed binary '${_bin_dir}/${_src_bin##*/}'."
      file__rm -f "${_bin_dir}/${_src_bin##*/}" 2>/dev/null || true
    done
  fi
  if [[ -v BINARY_COMPANION_BINS && "${#BINARY_COMPANION_BINS[@]}" -gt 0 ]]; then
    local _comp_name
    for _comp_name in "${BINARY_COMPANION_BINS[@]+"${BINARY_COMPANION_BINS[@]}"}"; do
      [[ -n "${_comp_name}" ]] || continue
      logging__remove "Removing companion symlink '${_bin_dir}/${_comp_name}'."
      file__rm -f "${_bin_dir}/${_comp_name}" 2>/dev/null || true
    done
  fi
  __run_feature_hook__ __uninstall_run_prefix_post
}

__uninstall_run_npm__() {
  __run_feature_hook__ __uninstall_run_npm_pre
  if [[ -z "${NPM_PACKAGE:-}" ]]; then
    logging__error "Cannot auto-uninstall npm-managed install: _options.method.npm not declared in metadata."
    return 1
  fi
  logging__remove "Uninstalling npm package '${NPM_PACKAGE}'."
  npm__uninstall_package --package "${NPM_PACKAGE}"
  __run_feature_hook__ __uninstall_run_npm_post
}

__uninstall_run_npm_bundled__() {
  __run_feature_hook__ __uninstall_run_npm_bundled_pre
  logging__remove "Uninstalling npm-bundled install at '${_FEAT_EXISTING_PATH}'."
  npm__uninstall_bundled --bin "${_FEAT_EXISTING_PATH}"
  __run_feature_hook__ __uninstall_run_npm_bundled_post
}

__uninstall_run_package__() {
  __run_feature_hook__ __uninstall_run_package_pre
  logging__remove "Uninstalling package dependencies."
  __dep_uninstall_for_method__ package
  __run_feature_hook__ __uninstall_run_package_post
}

__uninstall_run_upstream_package__() {
  __run_feature_hook__ __uninstall_run_upstream_package_pre
  logging__remove "Uninstalling upstream-package dependencies."
  __dep_uninstall_for_method__ upstream-package
  __run_feature_hook__ __uninstall_run_upstream_package_post
}

__uninstall_run_git_clone__() {
  __run_feature_hook__ __uninstall_run_git_clone_pre
  if [[ -z "${_FEAT_EXISTING_PATH:-}" ]]; then
    logging__skip "_FEAT_EXISTING_PATH empty; nothing to remove for git-clone uninstall."
    return 0
  fi
  logging__remove "Removing git-clone directory '${_FEAT_EXISTING_PATH}'."
  file__rm -rf "${_FEAT_EXISTING_PATH}"
  __run_feature_hook__ __uninstall_run_git_clone_post
}

__uninstall_shell_completions__() {
  [[ -v SHELL_COMPLETIONS ]] || {
    logging__skip "SHELL_COMPLETIONS unset; skipping completion removal."
    return 0
  }
  local _name="${_FEAT_CONTRACT_PRIMARY_BIN:-}"
  [[ -n "${_name}" ]] || {
    logging__skip "No primary binary name; skipping completion removal."
    return 0
  }
  logging__remove "Removing shell completions for '${_name}'."
  local _is_system=false _home
  if [[ "${PREFIX_SCOPE:-}" = "user" ]]; then
    _home="$(users__home_of_path_owner "${_RESOLVED_PREFIX}")"
  else
    _is_system=true
    _home="$(users__resolve_home)"
  fi
  local _shell
  for _shell in "${SHELL_COMPLETIONS[@]}"; do
    [ -z "$_shell" ] && continue
    logging__remove "Removing '${_shell}' completion for '${_name}'."
    case "$_shell" in
      bash)
        if "${_is_system}"; then
          file__rm "/etc/bash_completion.d/${_name}" 2>/dev/null || true
        else
          file__rm "${_home}/.local/share/bash-completion/completions/${_name}" 2>/dev/null || true
        fi
        ;;
      zsh)
        if "${_is_system}"; then
          file__rm "$(shell__detect_zshdir)/completions/_${_name}" 2>/dev/null || true
        else
          file__rm "${_home}/.zfunc/_${_name}" 2>/dev/null || true
        fi
        ;;
      fish)
        if "${_is_system}"; then
          file__rm "/usr/share/fish/vendor_completions.d/${_name}.fish" 2>/dev/null || true
        else
          file__rm "${_home}/.config/fish/completions/${_name}.fish" 2>/dev/null || true
        fi
        ;;
      nushell)
        file__rm "${_home}/.config/nushell/autoload/${_name}.nu" 2>/dev/null || true
        ;;
      elvish)
        local _rc="${_home}/.config/elvish/rc.elv"
        [ -f "$_rc" ] && shell__sync_block --files "$_rc" --marker "${_name} completion" || true
        ;;
    esac
  done
}

__cleanup_install_artifacts__() {
  logging__clean "Cleaning up install artifacts."
  if argparse__var_declared PREFIX; then
    # 1. Remove downstream symlinks and PATH export blocks.
    if [[ -v PREFIX_DISCOVERY ]]; then
      logging__remove "Removing prefix PATH discovery for '${_FEAT_ID}'."
      local -a _disc_args=()
      __feat_build_prefix_disc_args__ _disc_args
      shell__run_prefix_undiscovery "${_disc_args[@]}"
    fi
    # 2. Remove activation blocks from all applicable shell init files.
    if [[ -v PREFIX_ACTIVATIONS ]]; then
      logging__remove "Removing prefix activation snippets for '${_FEAT_ID}'."
      local _act_home_arg=""
      [ "${PREFIX_SCOPE}" = "user" ] && \
        _act_home_arg="$(users__home_of_path_owner "${_RESOLVED_PREFIX}")"
      shell__sync_config \
        --scope "${PREFIX_SCOPE}" \
        ${_act_home_arg:+--home "${_act_home_arg}"} \
        --marker "prefix activation (${_FEAT_ID})" \
        --profile-d "${_FEAT_ACTIVATION_PROFILE_D_FILE}" \
        "${PREFIX_ACTIVATIONS[@]}"
    fi
  else
    logging__skip "PREFIX unset; skipping prefix artifact cleanup."
  fi
  # 3. Remove shell completions.
  __uninstall_shell_completions__
  # 4. Unregister dummy PM package (no-op when not registered).
  if [[ -v REGISTER_PACKAGE_NAME && -n "${REGISTER_PACKAGE_NAME}" ]]; then
    logging__remove "Unregistering dummy package '${REGISTER_PACKAGE_NAME}'."
    ospkg__unregister_dummy "${REGISTER_PACKAGE_NAME}" 2>/dev/null || true
  else
    logging__skip "REGISTER_PACKAGE_NAME unset; skipping dummy package unregistration."
  fi
  # 5. Remove template-owned lifecycle and share directories.
  if [[ -d "${_FEAT_LIFECYCLE_DIR:-}" ]]; then
    logging__remove "Removing lifecycle directory '${_FEAT_LIFECYCLE_DIR}'."
    file__rm -rf "${_FEAT_LIFECYCLE_DIR}"
  fi
  if [[ -d "${_FEAT_SHARE_DIR_ROOT:-}" ]]; then
    logging__remove "Removing share directory '${_FEAT_SHARE_DIR_ROOT}'."
    file__rm -d "${_FEAT_SHARE_DIR_ROOT}" 2>/dev/null || true
  fi
  if [[ -d "${_FEAT_SHARE_DIR_NONROOT:-}" ]]; then
    logging__remove "Removing share directory '${_FEAT_SHARE_DIR_NONROOT}'."
    file__rm -d "${_FEAT_SHARE_DIR_NONROOT}" 2>/dev/null || true
  fi
  # 6. Feature-specific post-cleanup hook.
  __run_feature_hook__ __uninstall_finish_post
}

__uninstall_finish__() {

  __run_feature_hook__ __uninstall_finish_pre

  __cleanup_install_artifacts__
  _FEAT_EXISTING_PATH=""
  _FEAT_EXISTING_METHOD=""
  _FEAT_EXISTING=false
  logging__success "'${_FEAT_CONTRACT_PRIMARY_BIN:-tool}' uninstalled."
  # NOTE: __uninstall_finish_post is called inside __cleanup_install_artifacts__ (step 6).
}

# Installation
# ============
# Lifecycle orchestration: logging__info/install at each phase; plain calls between steps
# (set -eE + ERR/EXIT traps in __main__, inherit_errexit propagates into subshells).
# Each call site uses: cmd; local _rc=$?; [[ $_rc == 0 ]] || { logging__error "ctx"; return "$_rc"; }
# Never wrap lib calls in cmd || { … } — that disables errexit inside cmd.
__install__() {

  logging__info "Starting install (METHOD='${METHOD:-unset}', VERSION='${VERSION:-unset}')."

  __run_feature_hook__ __install_pre

  __install_init__
  __install_run__
  __install_finish__

  __run_feature_hook__ __install_post
}

__install_init__() {
  logging__debug "Starting install initialization."

  __run_feature_hook__ __install_init_pre

  __verify_system_requirements__
  __resolve_input_version__
  __resolve_input_method__
  __ctx_sync_pm_version__
  __resolve_input_prefixes__
  __dep_install_base__

  __run_feature_hook__ __install_init_post
}

__install_run__() {
  # Dispatches to the auto-implementation for each METHOD. Override
  # __install_run_<method>__ or use __install_run_<method>_pre/_post for custom logic.

  __run_feature_hook__ __install_run_pre

  local -a _dep_extra=()
  if [[ -v IF_EXISTS ]]; then
    case "${IF_EXISTS}" in
      update) _dep_extra+=(--update) ;;
      fail)   _dep_extra+=(--fail-if-installed) ;;
    esac
  fi
  __dep_install_option_bound__ "${_dep_extra[@]+"${_dep_extra[@]}"}"

  if [[ -v METHOD ]]; then
    __dep_install_for_method__
    logging__install "Running install for METHOD='${METHOD}'."
    case "${METHOD}" in
      binary)
        __install_run_binary__
        ;;
      package)
        __install_run_package__
        ;;
      upstream-package)
        __install_run_upstream_package__
        ;;
      script)
        __install_run_script__
        ;;
      cargo)
        __install_run_cargo__
        ;;
      npm)
        __install_run_npm__
        ;;
      npm-bundled)
        __install_run_npm_bundled__
        ;;
      source)
        __install_run_source__
        ;;
      git-clone)
        __install_run_git_clone__
        ;;
      *)
        logging__error "Unknown METHOD '${METHOD}': no auto-implementation exists. Override __install_run__."
        return 1
        ;;
    esac
    logging__info "Install run finished for METHOD='${METHOD}'."
  else
    logging__info "Install run finished (method-less feature)."
  fi

  __run_feature_hook__ __install_run_post
}

# Populate <out_arr> with (--sha256 <hex>) when VERSION_RESOLUTION is GitHub-based
# and the release API publishes a digest for <asset_name>.  No-op otherwise.
__github_release_sha256_args__() {
  local _asset_name="$1"
  local -n _out_arr="$2"
  _out_arr=()
  case "${VERSION_RESOLUTION:-}" in
    github_release | github_tag)
      [[ -n "${VERSION_URI:-}" && -n "${_FEAT_RESOLVED_TAG:-}" ]] || {
        logging__skip "VERSION_URI or _FEAT_RESOLVED_TAG unset; skipping GitHub SHA-256 probe for '${_asset_name}'."
        return 0
      }
      local _digest
      _digest="$(github__release_json_digest_from_uri \
        "${VERSION_URI}/releases/tags/${_FEAT_RESOLVED_TAG}" "$_asset_name")" || _digest=""
      if [[ -n "$_digest" ]]; then
        _out_arr=(--sha256 "$_digest")
      else
        logging__warn "no JSON digest for '${_asset_name}' in GitHub release metadata — skipping JSON SHA-256."
      fi
      ;;
  esac
}

__install_run_binary__() {
  __run_feature_hook__ __install_run_binary_pre
  if [[ -v BINARY_ASSET_URI && -n "${BINARY_ASSET_URI}" ]]; then
    if [[ ! -v VERSION ]]; then
      logging__error "METHOD=binary asset URI requires a version option; VERSION is unset (missing options.version in metadata?)."
      return 1
    fi
    local _asset_uri _asset_name _bin_dest _primary_name _src
    local -a _sha256_args=() _sidecar_args=() _installer_dir_arg=() _binary_src_args=() _netrc_arg=() _gpg_key_arg=() _gpg_sig_arg=()
    local -a _sidecar_gpg_key_arg=() _sidecar_gpg_sig_arg=()
    _asset_uri="$(ctx__expand_pattern "${BINARY_ASSET_URI}")"
    _asset_name="${_asset_uri%%\?*}"
    _asset_name="${_asset_name##*/}"
    if argparse__var_declared BINARY_SRC && [[ ${#BINARY_SRC[@]} -gt 0 ]]; then
      local -a _active_src=()
      mapfile -t _active_src < <(__feat_filter_binary_src__)
      if [[ ${#_active_src[@]} -eq 0 ]]; then
        logging__error "No binary_src entries matched the current install context (version/method/platform)."
        return 1
      fi
      for _src in "${_active_src[@]+"${_active_src[@]}"}"; do
        [[ -n "${_src}" ]] || continue
        _binary_src_args+=(--binary-src "${_src}")
      done
      _bin_dest="${_RESOLVED_PREFIX}/bin/"
      _primary_name="${_active_src[0]##*/}"
    else
      _bin_dest="${_RESOLVED_PREFIX}/bin/${_FEAT_CONTRACT_PRIMARY_BIN}"
      _primary_name="${_FEAT_CONTRACT_PRIMARY_BIN}"
    fi
    if [[ -v BINARY_SIDECAR_URI && -n "${BINARY_SIDECAR_URI}" ]]; then
      local _sc_uri
      _sc_uri="$(ctx__expand_pattern "${BINARY_SIDECAR_URI}")"
      _sidecar_args=(--sidecar "${_sc_uri}")
    fi
    # Use pre-computed SHA-256 (set by __install_run_binary_pre) when available;
    # otherwise probe from GitHub release metadata.
    if [[ -v BINARY_SHA256 && -n "${BINARY_SHA256}" ]]; then
      _sha256_args=(--sha256 "${BINARY_SHA256}")
    else
      __github_release_sha256_args__ "$_asset_name" _sha256_args
    fi
    if [[ -v BINARY_GPG_KEY_URI && -n "${BINARY_GPG_KEY_URI}" ]]; then
      local _gpg_key_uri
      _gpg_key_uri="$(ctx__expand_pattern "${BINARY_GPG_KEY_URI}")"
      _gpg_key_arg=(--gpg-key "${_gpg_key_uri}")
    fi
    if [[ -v BINARY_GPG_SIG_URI && -n "${BINARY_GPG_SIG_URI}" ]]; then
      local _gpg_sig_uri
      _gpg_sig_uri="$(ctx__expand_pattern "${BINARY_GPG_SIG_URI}")"
      _gpg_sig_arg=(--gpg-sig "${_gpg_sig_uri}")
    fi
    if [[ -v BINARY_SIDECAR_GPG_KEY_URI && -n "${BINARY_SIDECAR_GPG_KEY_URI}" ]]; then
      local _sidecar_gpg_key_uri
      _sidecar_gpg_key_uri="$(ctx__expand_pattern "${BINARY_SIDECAR_GPG_KEY_URI}")"
      _sidecar_gpg_key_arg=(--sidecar-gpg-key "${_sidecar_gpg_key_uri}")
    fi
    if [[ -v BINARY_SIDECAR_GPG_SIG_URI && -n "${BINARY_SIDECAR_GPG_SIG_URI}" ]]; then
      local _sidecar_gpg_sig_uri
      _sidecar_gpg_sig_uri="$(ctx__expand_pattern "${BINARY_SIDECAR_GPG_SIG_URI}")"
      _sidecar_gpg_sig_arg=(--sidecar-gpg-sig "${_sidecar_gpg_sig_uri}")
    fi
    [[ -n "${INSTALLER_DIR:-}" ]] && _installer_dir_arg=(--installer-dir "${INSTALLER_DIR}")
    [[ -n "${BINARY_NETRC:-}" ]] && _netrc_arg=(--netrc-file "${BINARY_NETRC}")
    logging__install "Installing binary '${_asset_name}' from '${_asset_uri}' to '${_bin_dest}'."
    install__release_asset \
      --asset-uri "${_asset_uri}" \
      "${_sha256_args[@]+"${_sha256_args[@]}"}" \
      "${_sidecar_args[@]+"${_sidecar_args[@]}"}" \
      "${_binary_src_args[@]+"${_binary_src_args[@]}"}" \
      --binary-dest "${_bin_dest}" \
      "${_installer_dir_arg[@]+"${_installer_dir_arg[@]}"}" \
      "${_netrc_arg[@]+"${_netrc_arg[@]}"}" \
      "${_gpg_key_arg[@]+"${_gpg_key_arg[@]}"}" \
      "${_gpg_sig_arg[@]+"${_gpg_sig_arg[@]}"}" \
      "${_sidecar_gpg_key_arg[@]+"${_sidecar_gpg_key_arg[@]}"}" \
      "${_sidecar_gpg_sig_arg[@]+"${_sidecar_gpg_sig_arg[@]}"}"
    if [[ -v BINARY_COMPANION_BINS && "${#BINARY_COMPANION_BINS[@]}" -gt 0 && -v _RESOLVED_PREFIX ]]; then
      local _comp_name
      for _comp_name in "${BINARY_COMPANION_BINS[@]+"${BINARY_COMPANION_BINS[@]}"}"; do
        [[ -n "${_comp_name}" ]] || continue
        logging__install "Creating companion symlink '${_RESOLVED_PREFIX}/bin/${_comp_name}' → '${_primary_name}'."
        # -sf: a *symlink* (not a hard link) whose relative target resolves in
        # the same bin dir, forced so a reinstall over an existing companion is
        # idempotent. Without -s this was `ln <relative-name> <link>`, a hard
        # link to a non-existent relative path that always failed.
        file__ln -sf "${_primary_name}" "${_RESOLVED_PREFIX}/bin/${_comp_name}"
      done
    fi
  else
    logging__error "METHOD=binary: no BINARY_ASSET_URI set (missing _options.method.binary in metadata?). Override __install_run_binary__ for a fully custom binary install."
    return 1
  fi
  __run_feature_hook__ __install_run_binary_post
}

__install_run_package__() {
  __run_feature_hook__ __install_run_package_pre
  __run_feature_hook__ __install_run_package_post
}

__install_run_upstream_package__() {
  __run_feature_hook__ __install_run_upstream_package_pre
  __run_feature_hook__ __install_run_upstream_package_post
}

__install_run_script__() {
  # Template-owned script pre-flight handled by __dep_install_for_method__ in __install_run__.

  __run_feature_hook__ __install_run_script_pre

  local _script_path
  if [[ -v SCRIPT_ASSET_URI && -n "${SCRIPT_ASSET_URI}" ]]; then
    local _asset_uri _asset_name
    local -a _sha256_args=() _sidecar_args=() _installer_dir_arg=() _netrc_arg=()
    _asset_uri="$(ctx__expand_pattern "${SCRIPT_ASSET_URI}")"
    _asset_name="${_asset_uri%%\?*}"
    _asset_name="${_asset_name##*/}"
    if [[ -v SCRIPT_SIDECAR_URI && -n "${SCRIPT_SIDECAR_URI}" ]]; then
      local _sc_uri
      _sc_uri="$(ctx__expand_pattern "${SCRIPT_SIDECAR_URI}")"
      _sidecar_args=(--sidecar "${_sc_uri}")
    fi
    __github_release_sha256_args__ "$_asset_name" _sha256_args
    [[ -n "${INSTALLER_DIR:-}" ]] && _installer_dir_arg=(--installer-dir "${INSTALLER_DIR}")
    [[ -n "${SCRIPT_NETRC:-}" ]] && _netrc_arg=(--netrc-file "${SCRIPT_NETRC}")
    local _asset_dir
    logging__download "Downloading script asset '${_asset_uri}'."
    _asset_dir="$(install__release_asset \
      --asset-uri "${_asset_uri}" \
      --chmod-exec "${_asset_name}" \
      "${_sha256_args[@]+"${_sha256_args[@]}"}" \
      "${_sidecar_args[@]+"${_sidecar_args[@]}"}" \
      "${_installer_dir_arg[@]+"${_installer_dir_arg[@]}"}" \
      "${_netrc_arg[@]+"${_netrc_arg[@]}"}")"
    local _rc=$?
    [[ $_rc == 0 ]] || { logging__error "failed to download release asset '${_asset_uri}'."; return "$_rc"; }
    _script_path="${_asset_dir}/${_asset_name}"
  else
    logging__error "METHOD=script: no SCRIPT_ASSET_URI set (missing _options.method.script in metadata?). Override __install_run_script__ for a fully custom script install."
    return 1
  fi

  logging__launch "Running install script '${_script_path}'."
  if declare -f __install_run_script_run > /dev/null; then
    __run_feature_hook__ __install_run_script_run "${_script_path}"
  else
    logging__debug "No feature hook '__install_run_script_run' found; running script directly."
    local -a _all_script_args=()
    if [[ -v SCRIPT_ARGS ]]; then __expand_args__ SCRIPT_ARGS _all_script_args; fi
    if [[ -v _FEAT_INSTALL_SCRIPT_ARGS ]]; then
      _all_script_args+=("${_FEAT_INSTALL_SCRIPT_ARGS[@]+"${_FEAT_INSTALL_SCRIPT_ARGS[@]}"}")
    fi
    "${_script_path}" "${_all_script_args[@]+"${_all_script_args[@]}"}"
  fi

  __run_feature_hook__ __install_run_script_post
}

__install_run_cargo__() {
  # Auto-implementation for METHOD=cargo.
  #
  # Command selection (in priority order):
  #   1. _FEAT_CARGO_COMMAND array set by __install_run_cargo_pre — use verbatim.
  #   2. cargo-binstall available — prefer it (downloads pre-built binary; falls
  #      back to source compilation automatically when no binary is published).
  #   3. cargo install — compile from source.
  #
  # Standard args added automatically (before _FEAT_CARGO_INSTALL_ARGS):
  #   --root  ${PREFIX}   when prefix is configured.
  #   --version ${VERSION}                    when VERSION is set.
  #
  # _FEAT_CARGO_INSTALL_ARGS (array): set in __install_run_cargo_pre to pass
  #   any additional args (e.g. --force, --locked, --no-confirm).
  #   Appended after the standard args above.

  command -v cargo > /dev/null 2>&1 || {
    logging__error "METHOD=cargo requires 'cargo' on PATH. Install Rust and Cargo first."
    return 1
  }
  __run_feature_hook__ __install_run_cargo_pre

  if [[ -z "${CARGO_CRATE:-}" ]]; then
    logging__error "METHOD=cargo: no CARGO_CRATE set (missing _options.method.cargo in metadata?). Override __install_run_cargo__ for a fully custom cargo install."
    return 1
  fi

  local -a _cargo_cmd
  local -a _cargo_args=()
  if [[ -v _FEAT_CARGO_COMMAND ]]; then
    _cargo_cmd=("${_FEAT_CARGO_COMMAND[@]}")
  elif command -v cargo-binstall > /dev/null 2>&1; then
    _cargo_cmd=(cargo binstall)
    _cargo_args+=(--no-confirm)
    logging__info "Using cargo-binstall for crate '${CARGO_CRATE}'."
  else
    _cargo_cmd=(cargo install)
    logging__info "Using cargo install for crate '${CARGO_CRATE}'."
  fi
  if [[ -v _FEAT_CARGO_COMMAND ]]; then
    logging__info "Using custom cargo command for crate '${CARGO_CRATE}': '${_cargo_cmd[*]}'."
  fi
  if [[ -v _RESOLVED_PREFIX ]]; then
    _cargo_args+=(--root "${_RESOLVED_PREFIX}")
  fi
  [[ -v VERSION && -n "${VERSION}" ]] && _cargo_args+=(--version "${VERSION}")
  if [[ -v CARGO_INSTALL_ARGS ]]; then __expand_args__ CARGO_INSTALL_ARGS _cargo_args; fi
  if [[ -v _FEAT_CARGO_INSTALL_ARGS ]]; then
    _cargo_args+=("${_FEAT_CARGO_INSTALL_ARGS[@]+"${_FEAT_CARGO_INSTALL_ARGS[@]}"}")
  fi

  logging__install "Installing cargo crate '${CARGO_CRATE}' via '${_cargo_cmd[*]}'."
  "${_cargo_cmd[@]}" "${CARGO_CRATE}" "${_cargo_args[@]+"${_cargo_args[@]}"}"

  __run_feature_hook__ __install_run_cargo_post
}

__install_run_npm__() {
  command -v npm > /dev/null 2>&1 || {
    logging__error "METHOD=npm requires 'npm' on PATH. Install Node.js/npm first (e.g. via the 'install-node' or 'install-nvm' feature)."
    return 1
  }
  __run_feature_hook__ __install_run_npm_pre
  if [[ -z "${NPM_PACKAGE:-}" ]]; then
    logging__error "METHOD=npm: no NPM_PACKAGE set (missing _options.method.npm in metadata?). Override __install_run_npm__ for a fully custom npm install."
    return 1
  fi

  # Build versioned package spec (pkg@version; omit for 'latest' since npm handles it).
  local _pkg="${NPM_PACKAGE}"
  [[ -v VERSION && -n "${VERSION}" && "${VERSION}" != "latest" ]] && _pkg+="@${VERSION}"

  local -a _install_args=(install -g)
  # Install into feature prefix when configured.
  if [[ -v _RESOLVED_PREFIX ]]; then
    _install_args+=(--prefix "${_RESOLVED_PREFIX}")
  fi
  [[ -n "${NPM_REGISTRY:-}" ]] && _install_args+=(--registry "${NPM_REGISTRY}")
  if [[ -v NPM_INSTALL_ARGS ]]; then __expand_args__ NPM_INSTALL_ARGS _install_args; fi
  _install_args+=("${_pkg}")

  logging__install "Installing npm package '${_pkg}'."
  npm "${_install_args[@]}"

  __run_feature_hook__ __install_run_npm_post
}

__install_run_npm_bundled__() {
  # Auto-implementation for METHOD=npm-bundled.
  #
  # Installs NPM_PACKAGE with a self-contained bundled Node.js runtime using
  # npm__install_bundled. The runtime is isolated from any system Node.js.
  #
  # Passes --update when _FEAT_EXISTING_PATH is non-empty (update flow).
  # _FEAT_EXISTING_PATH is cleared by __uninstall_finish__ before reinstall or
  # method-migration, so --update is absent in those cases even when METHOD
  # remains npm-bundled.
  #
  # Use __install_run_npm_bundled_pre for pre-install setup (e.g. dep installs).
  # Override __install_run_npm_bundled__ entirely for full control.

  __run_feature_hook__ __install_run_npm_bundled_pre

  if [[ -z "${NPM_PACKAGE:-}" ]]; then
    logging__error "METHOD=npm-bundled: no NPM_PACKAGE set (missing _options.method.npm-bundled in metadata?). Override __install_run_npm_bundled__ for a fully custom npm-bundled install."
    return 1
  fi

  local -a _flags=() _cmd_arg=() _registry_arg=()
  [[ -n "${_FEAT_EXISTING_PATH:-}" ]] && _flags+=(--update)
  [[ -v NPM_CMD ]] && _cmd_arg=(--cmd "${NPM_CMD}")
  [[ -n "${NPM_REGISTRY:-}" ]] && _registry_arg=(--registry "${NPM_REGISTRY}")

  logging__install "Installing npm-bundled package '${NPM_PACKAGE}' into '${_RESOLVED_PREFIX}'."
  # shellcheck disable=SC2153  # NODE_VERSION is set via argparse for npm-bundled features; not a typo of NODE_VERSIONS
  npm__install_bundled \
    --package "${NPM_PACKAGE}" \
    "${_cmd_arg[@]+"${_cmd_arg[@]}"}" \
    --prefix "${_RESOLVED_PREFIX}" \
    --version "${VERSION}" \
    --node-version "${NODE_VERSION}" \
    "${_registry_arg[@]+"${_registry_arg[@]}"}" \
    "${_flags[@]+"${_flags[@]}"}"

  __run_feature_hook__ __install_run_npm_bundled_post
}

__install_run_source__() {
  # Auto-implementation for METHOD=source.
  #
  # Downloads the source archive declared in SOURCE_ASSET_URI (with optional
  # SOURCE_SIDECAR_URI verification), extracts it to ${INSTALLER_DIR}/asset/,
  # then dispatches to the build step.
  #
  # Build dispatch (in priority order):
  #   1. __install_run_source_build <src_dir>  — explicit feature hook.
  #      Receives the path to the top-level extracted directory.  Use this
  #      whenever the build requires logic that cannot be expressed declaratively
  #      (e.g. platform-specific flags, post-install steps, multiple make passes).
  #   2. __install_run_source_auto_build__ <src_dir> — framework auto-impl.
  #      Driven by SOURCE_BUILD_SYSTEM / SOURCE_CONFIGURE_ARGS / SOURCE_CMAKE_ARGS /
  #      SOURCE_BUILD_ENV (injected via env) / SOURCE_MAKE_FLAGS / SOURCE_MAKE_TARGETS.
  #      Covers autotools, bare make, and cmake.
  #      Active when SOURCE_BUILD_SYSTEM is non-empty.
  #
  # Use __install_run_source_pre for pre-build setup (e.g. installing build deps
  # that cannot be expressed in _dependencies.build).  Override
  # __install_run_source__ entirely only when you need a fully custom fetch+build.

  # Template-owned source pre-flight (runs before the optional feature hook):
  # 1. Create the install prefix directory.
  [[ -v _RESOLVED_PREFIX ]] && file__mkdir "${_RESOLVED_PREFIX}"
  # 2. On macOS, ensure Xcode CLI tools are available (installs headlessly if absent).
  [[ "$(os__kernel)" == "Darwin" ]] && bootstrap__xcode
  # 3. method-source build deps installed by __dep_install_for_method__ in __install_run__.

  __run_feature_hook__ __install_run_source_pre

  if [[ ! -v SOURCE_ASSET_URI || -z "${SOURCE_ASSET_URI}" ]]; then
    logging__error "METHOD=source: no SOURCE_ASSET_URI set (missing _options.method.source.asset_uri in metadata?). Override __install_run_source__ for a fully custom source install."
    return 1
  fi

  local _asset_uri
  _asset_uri="$(ctx__expand_pattern "${SOURCE_ASSET_URI}")"

  local -a _fetch_args=(--installer-dir "${INSTALLER_DIR}")
  if [[ -v SOURCE_SIDECAR_URI && -n "${SOURCE_SIDECAR_URI}" ]]; then
    local _sc_uri
    _sc_uri="$(ctx__expand_pattern "${SOURCE_SIDECAR_URI}")"
    _fetch_args+=(--sidecar "${_sc_uri}")
  fi

  logging__download "Fetching source asset '${_asset_uri}'."
  local _fetch_rc=0
  uri__fetch_asset "${_asset_uri}" "${_fetch_args[@]}" || _fetch_rc=$?
  if [[ ${_fetch_rc} -ne 0 ]]; then
    if [[ -v SOURCE_FALLBACK_ASSET_URI && -n "${SOURCE_FALLBACK_ASSET_URI}" ]]; then
      local _fallback_uri
      _fallback_uri="$(ctx__expand_pattern "${SOURCE_FALLBACK_ASSET_URI}")"
      logging__warn "Primary source fetch failed (rc=${_fetch_rc}); trying fallback '${_fallback_uri}'."
      uri__fetch_asset "${_fallback_uri}" --installer-dir "${INSTALLER_DIR}" --sha256 none
    else
      return "${_fetch_rc}"
    fi
  fi

  local _src_dir
  _src_dir="$(file__first_child_dir "${INSTALLER_DIR}/asset")"
  if [[ -z "${_src_dir}" ]]; then
    logging__error "METHOD=source: no directory found under '${INSTALLER_DIR}/asset' after extraction."
    return 1
  fi

  logging__build "Building source from '${_src_dir}' (SOURCE_BUILD_SYSTEM='${SOURCE_BUILD_SYSTEM:-unset}')."
  if declare -f __install_run_source_build > /dev/null; then
    __run_feature_hook__ __install_run_source_build "${_src_dir}"
  else
    logging__debug "No feature hook '__install_run_source_build' found; using auto-build."
    __install_run_source_auto_build__ "${_src_dir}"
    __install_run_source_auto_install_bins__ "${_src_dir}"
  fi

  __run_feature_hook__ __install_run_source_post
}

__install_run_source_auto_build__() {
  # Framework auto-build for METHOD=source, driven by SOURCE_BUILD_SYSTEM.
  # Called when __install_run_source_build is not defined.
  # Supports SOURCE_BUILD_SYSTEM=autotools, SOURCE_BUILD_SYSTEM=make, and
  # SOURCE_BUILD_SYSTEM=cmake.
  local _src_dir="$1"
  local _jobs
  _jobs="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || printf '1')"

  local -a _make_flags=()
  if [[ -v SOURCE_MAKE_FLAGS ]]; then __expand_args__ SOURCE_MAKE_FLAGS _make_flags; fi

  local -a _make_targets=()
  if [[ -v SOURCE_MAKE_TARGETS ]]; then __expand_args__ SOURCE_MAKE_TARGETS _make_targets; fi
  if [[ "${#_make_targets[@]}" -eq 0 ]]; then _make_targets=(all install); fi

  local -a _build_env=()
  __feat_collect_source_build_env__ _build_env || return 1

  case "${SOURCE_BUILD_SYSTEM:-}" in
    autotools)
      local -a _configure_args=()
      if [[ -v SOURCE_CONFIGURE_ARGS ]]; then __expand_args__ SOURCE_CONFIGURE_ARGS _configure_args; fi
      if [[ -v _RESOLVED_PREFIX ]]; then
        _configure_args+=(--prefix="${_RESOLVED_PREFIX}")
      fi
      (
        cd "${_src_dir}" || {
          logging__error "Autotools build: failed to cd to '${_src_dir}'."
          exit 1
        }
        env "${_build_env[@]+"${_build_env[@]}"}" \
          ./configure "${_configure_args[@]+"${_configure_args[@]}"}" || {
          logging__error "Autotools build: configure failed in '${_src_dir}'."
          exit 1
        }
        local _t
        for _t in "${_make_targets[@]}"; do
          env "${_build_env[@]+"${_build_env[@]}"}" \
            make -j"${_jobs}" "${_make_flags[@]+"${_make_flags[@]}"}" "${_t}" || {
            logging__error "Autotools build: make target '${_t}' failed in '${_src_dir}'."
            exit 1
          }
        done
      ) || {
        logging__error "Autotools build failed in '${_src_dir}' (SOURCE_BUILD_SYSTEM=autotools)."
        return 1
      }
      ;;
    make)
      (
        cd "${_src_dir}" || {
          logging__error "Make build: failed to cd to '${_src_dir}'."
          exit 1
        }
        local _t
        for _t in "${_make_targets[@]}"; do
          env "${_build_env[@]+"${_build_env[@]}"}" \
            make -j"${_jobs}" "${_make_flags[@]+"${_make_flags[@]}"}" "${_t}" || {
            logging__error "Make build: make target '${_t}' failed in '${_src_dir}'."
            exit 1
          }
        done
      ) || {
        logging__error "Make build failed in '${_src_dir}' (SOURCE_BUILD_SYSTEM=make)."
        return 1
      }
      ;;
    cmake)
      local -a _cmake_args=()
      if [[ -v SOURCE_CMAKE_ARGS ]]; then __expand_args__ SOURCE_CMAKE_ARGS _cmake_args; fi
      local -a _cmake_prefix_arg=()
      if [[ -v _RESOLVED_PREFIX ]]; then
        _cmake_prefix_arg=(-DCMAKE_INSTALL_PREFIX="${_RESOLVED_PREFIX}")
      fi
      env "${_build_env[@]+"${_build_env[@]}"}" \
        cmake -S "${_src_dir}" -B "${_src_dir}/build" -DCMAKE_BUILD_TYPE=Release \
        "${_cmake_prefix_arg[@]+"${_cmake_prefix_arg[@]}"}" "${_cmake_args[@]+"${_cmake_args[@]}"}" || {
        logging__error "CMake build: configure failed in '${_src_dir}'."
        return 1
      }
      env "${_build_env[@]+"${_build_env[@]}"}" \
        cmake --build "${_src_dir}/build" --parallel "${_jobs}" || {
        logging__error "CMake build: build step failed in '${_src_dir}'."
        return 1
      }
      env "${_build_env[@]+"${_build_env[@]}"}" \
        cmake --install "${_src_dir}/build" || {
        logging__error "CMake build: install step failed in '${_src_dir}'."
        return 1
      }
      ;;
    "")
      logging__error "METHOD=source: SOURCE_BUILD_SYSTEM is not set. Define __install_run_source_build or set source_build_system in metadata."
      return 1
      ;;
    *)
      logging__error "METHOD=source: SOURCE_BUILD_SYSTEM='${SOURCE_BUILD_SYSTEM}' is not supported. Use 'autotools', 'make', or 'cmake', or define __install_run_source_build."
      return 1
      ;;
  esac
}

__feat_collect_source_build_env__() {
  # Populate caller-supplied array with validated, expanded SOURCE_BUILD_ENV entries.
  # Usage: __feat_collect_source_build_env__ <dst_array_name>
  local -n _fcse_dst="$1"
  if ! argparse__var_declared SOURCE_BUILD_ENV || [[ ${#SOURCE_BUILD_ENV[@]} -eq 0 ]]; then
    return 0
  fi
  local -a _active_env=()
  mapfile -t _active_env < <(__feat_filter_source_build_env__)
  [[ ${#_active_env[@]} -gt 0 ]] || return 0
  local -a _expanded_env=()
  __expand_args__ _active_env _expanded_env
  local _entry
  for _entry in "${_expanded_env[@]+"${_expanded_env[@]}"}"; do
    [[ -n "${_entry}" ]] || continue
    if [[ ! "${_entry}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
      logging__error "SOURCE_BUILD_ENV entry '${_entry}' is not a valid NAME=value assignment."
      return 1
    fi
    _fcse_dst+=("${_entry}")
  done
}

__install_run_source_auto_install_bins__() {
  local _src_dir="$1"
  [[ -v _RESOLVED_PREFIX && -n "${_RESOLVED_PREFIX}" ]] || {
    logging__error "METHOD=source: PREFIX is not resolved; cannot auto-install built binaries."
    return 1
  }
  if ! argparse__var_declared SOURCE_INSTALL_BINS || [[ ${#SOURCE_INSTALL_BINS[@]} -eq 0 ]]; then
    logging__skip "SOURCE_INSTALL_BINS not declared; skipping post-build binary copy."
    return 0
  fi

  local _src _src_path
  local -a _active_bins=()
  mapfile -t _active_bins < <(__feat_filter_source_install_bins__)
  if [[ ${#_active_bins[@]} -eq 0 ]]; then
    logging__error "No source_install_bins entries matched the current install context (version/method/platform)."
    return 1
  fi

  local -a _expanded_bins=()
  __expand_args__ _active_bins _expanded_bins

  for _src in "${_expanded_bins[@]+"${_expanded_bins[@]}"}"; do
    [[ -n "${_src}" ]] || continue
    _src_path="${_src}"
    [[ "${_src_path}" = /* ]] || _src_path="${_src_dir}/${_src_path}"
    install__copy_bin "${_src_path}" "${_RESOLVED_PREFIX}/bin/${_src##*/}" || {
      logging__error "Failed to copy built binary '${_src_path}' → '${_RESOLVED_PREFIX}/bin/${_src##*/}'."
      return 1
    }
  done
}

# Apply git config entries from GIT_CLONE_CONFIG after a git-clone install or update.
# Each element of GIT_CLONE_CONFIG is a `key=value` pair; values support {feat.version} substitution.
_git_clone_apply_config() {
  local _dir="$1" _ver="$2"
  [[ -v GIT_CLONE_CONFIG ]] || {
    logging__skip "GIT_CLONE_CONFIG unset; skipping git config application in '${_dir}'."
    return 0
  }
  ((${#GIT_CLONE_CONFIG[@]} == 0)) && {
    logging__skip "GIT_CLONE_CONFIG empty; skipping git config application in '${_dir}'."
    return 0
  }
  local -a _expanded=()
  local _pair _val
  for _pair in "${GIT_CLONE_CONFIG[@]}"; do
    _val="${_pair#*=}"
    _val="$(ctx__expand_pattern "${_val}")"
    [[ -n "${_val}" ]] || {
      logging__warn "skipping config key '${_pair%%=*}' — value is empty after VERSION substitution."
      continue
    }
    _expanded+=("${_pair%%=*}=${_val}")
  done
  ((${#_expanded[@]} == 0)) && {
    logging__skip "No git config entries to apply in '${_dir}' after VERSION substitution."
    return 0
  }
  logging__install "Applying ${#_expanded[@]} git config entries in '${_dir}'."
  git__config "${_dir}" "${_expanded[@]}"
}

__install_run_git_clone__() {
  __run_feature_hook__ __install_run_git_clone_pre
  if [[ -z "${GIT_CLONE_URI:-}" ]]; then
    logging__error "METHOD=git-clone: GIT_CLONE_URI not set (missing _options.method.git-clone.uri in metadata?)."
    return 1
  fi
  if [[ -z "${_RESOLVED_PREFIX:-}" ]]; then
    logging__error "METHOD=git-clone: PREFIX is not set. Declare _options.prefix.root/nonroot in the feature's metadata.yaml."
    return 1
  fi
  local _uri
  _uri="$(ctx__expand_pattern "${GIT_CLONE_URI}")"
  local _ref_arg=()
  [[ -v VERSION && -n "${VERSION}" ]] && _ref_arg=(--ref "${VERSION}")
  local _sha_arg=()
  [[ -n "${_FEAT_RESOLVED_GIT_SHA:-}" ]] && _sha_arg=(--resolved-sha "${_FEAT_RESOLVED_GIT_SHA}")
  logging__install "Cloning '${_uri}' into '${_RESOLVED_PREFIX}' (ref='${VERSION:-HEAD}')."
  git__clone --url "${_uri}" --dir "${_RESOLVED_PREFIX}" "${_ref_arg[@]+"${_ref_arg[@]}"}" "${_sha_arg[@]+"${_sha_arg[@]}"}"
  _git_clone_apply_config "${_RESOLVED_PREFIX}" "${VERSION:-}"
  __run_feature_hook__ __install_run_git_clone_post
}

__install_register_dummy__() {
  # Register a dummy OS package so downstream Depends: constraints are satisfied.
  # Only runs when REGISTER_PACKAGE_NAME is set and METHOD is a non-PM method.
  # Debian/Ubuntu only; no-op elsewhere (ospkg__register_dummy handles the guard).
  [[ -v REGISTER_PACKAGE_NAME && -n "${REGISTER_PACKAGE_NAME}" ]] || {
    logging__skip "REGISTER_PACKAGE_NAME unset; skipping dummy package registration."
    return 0
  }
  case "${METHOD:-}" in
    package | upstream-package)
      logging__skip "METHOD='${METHOD}'; skipping dummy registration for '${REGISTER_PACKAGE_NAME}'."
      return 0
      ;;
  esac
  [[ -v VERSION && -n "${VERSION}" ]] || {
    logging__warn "VERSION not set; skipping dummy registration for '${REGISTER_PACKAGE_NAME}'."
    return 0
  }
  ospkg__register_dummy "${REGISTER_PACKAGE_NAME}" "${VERSION}"
}

__install_shell_completions__() {
  # shellcheck disable=SC2329,SC2317
  [[ -v SHELL_COMPLETIONS && "${#SHELL_COMPLETIONS[@]}" -gt 0 ]] || {
    logging__skip "SHELL_COMPLETIONS unset or empty; skipping shell completions."
    return 0
  }

  local _name="${_FEAT_CONTRACT_PRIMARY_BIN:-}"
  if [[ -z "${_name}" ]]; then
    logging__warn "No completion name resolved; skipping shell completions."
    return 0
  fi

  local _scope_flag="" _home
  if ! users__is_user_path "${_RESOLVED_PREFIX}"; then
    _scope_flag="--system"
    _home="$(users__resolve_home)"
  else
    _home="$(users__home_of_path_owner "${_RESOLVED_PREFIX}")"
  fi

  declare -A _completion_files_map
  if [[ -v SHELL_COMPLETIONS_FILES ]]; then
    local _entry _k _v
    for _entry in "${SHELL_COMPLETIONS_FILES[@]}"; do
      _k="${_entry%%=*}"
      _v="${_entry#*=}"
      [[ -n "${_k}" ]] && _completion_files_map["${_k}"]="${_v}"
    done
  fi

  local _shell
  for _shell in "${SHELL_COMPLETIONS[@]}"; do
    local _content=""
    if declare -f __get_completion_content__ > /dev/null; then
      _content="$(__get_completion_content__ "${_shell}")" || {
        logging__warn "__get_completion_content__ for '${_shell}' failed; skipping."
        continue
      }
    elif [[ -n "${_completion_files_map[${_shell}]+x}" ]]; then
      local _src="${_RESOLVED_PREFIX}/${_completion_files_map[${_shell}]}"
      _content="$(cat "${_src}" 2> /dev/null)" || {
        logging__warn "Completion source file '${_src}' not found; skipping '${_shell}'."
        continue
      }
    elif [[ -n "${SHELL_COMPLETIONS_CMD:-}" ]]; then
      local _bin="${_RESOLVED_PREFIX}/bin/${_FEAT_CONTRACT_PRIMARY_BIN}"
      command -v "${_bin}" > /dev/null 2>&1 \
        || _bin="$(command -v "${_FEAT_CONTRACT_PRIMARY_BIN}" 2> /dev/null)" || {
        logging__warn "Binary '${_FEAT_CONTRACT_PRIMARY_BIN}' not found; skipping shell completions."
        return 0
      }
      # shellcheck disable=SC2086
      _content="$("${_bin}" ${SHELL_COMPLETIONS_CMD} "${_shell}" 2> /dev/null)" || {
        logging__warn "Completion command '${_FEAT_CONTRACT_PRIMARY_BIN} ${SHELL_COMPLETIONS_CMD} ${_shell}' failed; skipping."
        continue
      }
    else
      logging__warn "No completion source for '${_shell}'; skipping."
      continue
    fi
    logging__install "Installing '${_shell}' completion for '${_name}'."
    shell__install_completion ${_scope_flag:+"${_scope_flag}"} --home "${_home}" \
      "${_shell}" "${_name}" "${_content}"
  done
}

# Returns 0 when this installation method is covered by the prefix config.
# When no guard var is configured (_FEAT_PREFIX_GUARD_VAR is empty) every method qualifies.
__feat_prefix_applies__() {
  [[ -z "${_FEAT_PREFIX_GUARD_VAR:-}" ]] && return 0
  local _val="${!_FEAT_PREFIX_GUARD_VAR:-}"
  local _v
  for _v in ${_FEAT_PREFIX_GUARD_VALS}; do
    [[ "${_val}" == "${_v}" ]] && return 0
  done
  return 1
}

# Populate the named array ref with the discovery args shared by __install_finish__ and
# __cleanup_install_artifacts__. Requires PREFIX, PREFIX_DISCOVERY, and related vars to be set.
__feat_build_prefix_disc_args__() {
  declare -n _fpda_out="$1"
  _fpda_out=(
    --prefix "${_RESOLVED_PREFIX}"
    --bin-dir "${PREFIX_BIN_DIR}"
    --discovery "${PREFIX_DISCOVERY}"
    --runtime-path "${_RESOLVED_RUNTIME_PATH:-}"
    --bin "${_FEAT_CONTRACT_PRIMARY_BIN}"
    --cmd-var "_DF_EXPECTED_CMD"
    --marker "${_FEAT_CONTRACT_PRIMARY_BIN:+${_FEAT_CONTRACT_PRIMARY_BIN} }PATH (${_FEAT_ID})"
  )
  [[ -v PREFIX_BINS ]] && _fpda_out+=(--bins "${PREFIX_BINS[*]}")
  # argparse__var_declared detects declared-but-empty arrays; [[ -v arr ]] does not
  # (it checks arr[0], returning false for empty arrays). Use bare function calls in
  # && / || chains: ERR trap fires for commands inside { ... } even when conditional.
  argparse__var_declared PREFIX_SYMLINKS && _fpda_out+=(
    --symlinks-ref "PREFIX_SYMLINKS"
    --symlink-root "${PREFIX_SYMLINK_ROOT}"
    --symlink-nonroot "${PREFIX_SYMLINK_NONROOT}"
  )
  argparse__var_declared PREFIX_EXPORTS && _fpda_out+=(
    --exports-ref "PREFIX_EXPORTS"
    --profile-d "${_FEAT_PROFILE_D_FILE}"
  )
  argparse__var_declared PREFIX_SYMLINKS || _fpda_out+=(--no-symlinks)
  argparse__var_declared PREFIX_EXPORTS || _fpda_out+=(--no-exports)
  # Per-shell discovery snippets: user-provided option takes priority, then
  # feature hook __prefix_discovery_snippet__ (if defined), then generic PATH.
  # Use 'if' for the outer guard so the function always exits 0 even when
  # PREFIX_EXPORTS is not declared (a &&-chain guard would propagate exit 1).
  if argparse__var_declared PREFIX_EXPORTS; then
    local _fpda_shells=(bash zsh fish tcsh elvish)
    local _fpda_shell
    for _fpda_shell in "${_fpda_shells[@]}"; do
      local _fpda_snippet=""
      local _fpda_var="PREFIX_DISCOVERY_SNIPPET_${_fpda_shell^^}"
      if argparse__var_declared "$_fpda_var" && [[ -n "${!_fpda_var}" ]]; then
        _fpda_snippet="$(ctx__expand_pattern "${!_fpda_var}")"
      fi
      if [[ -z "$_fpda_snippet" ]] && declare -f __prefix_discovery_snippet__ > /dev/null; then
        _fpda_snippet="$(__prefix_discovery_snippet__ "$_fpda_shell")" || true
      fi
      if [[ -n "$_fpda_snippet" ]]; then
        _fpda_out+=("--${_fpda_shell}-snippet" "$_fpda_snippet")
      fi
    done
  fi
}

__install_finish__() {

  __run_feature_hook__ __install_finish_pre

  if argparse__var_declared PREFIX && __feat_prefix_applies__; then
    # -- discovery --
    [[ -v PREFIX_DISCOVERY ]] && {
      logging__install "Running prefix PATH discovery for '${_FEAT_ID}' into '${_RESOLVED_PREFIX}'."
      # Re-resolve RUNTIME_PATH for the case where __resolve_prefix__ had to skip
      # because the install user didn't exist yet (e.g. linuxbrew on a fresh host).
      # __install_run__ guarantees the user now exists, so expand here before use.
      if [[ -v RUNTIME_PATH && ! -v _RESOLVED_RUNTIME_PATH ]]; then
        declare -g _RESOLVED_RUNTIME_PATH
        _RESOLVED_RUNTIME_PATH="$(users__expand_path --user "${INSTALL_USER:-$(users__get_current)}" "$RUNTIME_PATH")"
        logging__info "Option 'runtime_path' re-resolved for discovery to '${_RESOLVED_RUNTIME_PATH}'."
      fi
      local -a _disc_args=()
      __feat_build_prefix_disc_args__ _disc_args
      shell__run_prefix_discovery "${_disc_args[@]}"
    }

    # -- activation --
    [[ -v PREFIX_ACTIVATIONS ]] && {
      logging__install "Writing prefix activation snippets for shells: ${PREFIX_ACTIVATIONS[*]}."
      local _act_home_arg=""
      [ "${PREFIX_SCOPE}" = "user" ] && \
        _act_home_arg="$(users__home_of_path_owner "${_RESOLVED_PREFIX}")"
      local -a _act_args=()
      local _asnip_shell
      for _asnip_shell in "${PREFIX_ACTIVATIONS[@]}"; do
        [ -z "$_asnip_shell" ] && continue
        if declare -f __prefix_activation_snippet > /dev/null; then
          local _asnip_content _asnip_rc
          _asnip_content="$(__prefix_activation_snippet "$_asnip_shell")" && _asnip_rc=0 || _asnip_rc=$?
          [ -z "$_asnip_content" ] && continue
          _act_args+=("--${_asnip_shell}-content" "$_asnip_content")
          if [ "$_asnip_rc" -eq 0 ]; then _act_args+=("--${_asnip_shell}-everywhere"); fi
        fi
      done
      [ "${#_act_args[@]}" -gt 0 ] && shell__sync_config \
        --scope "${PREFIX_SCOPE}" \
        ${_act_home_arg:+--home "${_act_home_arg}"} \
        --marker "prefix activation (${_FEAT_ID})" \
        --profile-d "${_FEAT_ACTIVATION_PROFILE_D_FILE}" \
        "${_act_args[@]}"
      unset _act_home_arg _act_args _asnip_shell
    }

    # -- write_group --
    [[ -n "${WRITE_GROUP:-}" ]] && {
      if users__is_privileged; then
        local _wargs=()
        if [[ "${#WRITE_USERS[@]}" -gt 0 ]]; then
          _wargs=(--current false --remote false --container false)
          for _u in "${WRITE_USERS[@]}"; do _wargs+=(--user "$_u"); done
        fi
        mapfile -t _write_users < <(users__resolve_list "${_wargs[@]}")
        logging__install "Configuring write group '${WRITE_GROUP}' on prefix '${_RESOLVED_PREFIX}'."
        users__set_write_permissions "${_RESOLVED_PREFIX}" \
          "${INSTALL_USER:-$(id -nu)}" "${WRITE_GROUP}" "${_write_users[@]}"
      else
        logging__warn "write_group='${WRITE_GROUP}' requested but no privilege available (groupadd/chown require root/sudo); skipping."
      fi
    }
  elif argparse__var_declared PREFIX; then
    logging__skip "PREFIX configured but prefix guard '${_FEAT_PREFIX_GUARD_VAR:-}'='${!_FEAT_PREFIX_GUARD_VAR:-}' does not apply for METHOD='${METHOD:-unset}'."
  else
    logging__skip "PREFIX unset; skipping prefix finish steps."
  fi

  __install_register_dummy__
  if [[ -v METHOD && -n "${METHOD:-}" ]]; then
    local _method_state_base="${_FEAT_SHARE_DIR_ROOT}"
    if users__is_user_path "${_RESOLVED_PREFIX:-${_FEAT_SHARE_DIR_ROOT}}"; then
      _method_state_base="${_FEAT_SHARE_DIR_NONROOT}"
    fi
    local _method_state_dir="${_method_state_base}/state"
    file__mkdir "${_method_state_dir}"
    printf '%s\n' "${METHOD}" | file__tee "${_method_state_dir}/installed-method"
    logging__info "Recorded installed method '${METHOD}' at '${_method_state_dir}'."
  fi
  ${{ _script.shell_completions_call }}$
  __deploy_lifecycle_scripts__
  ${{ _script.configure_users_call }}$

  __run_feature_hook__ __install_finish_post
  logging__success "Installation complete."
}

# Reinstallation
# ===============
__reinstall__() {

  logging__info "Starting reinstall (path='${_FEAT_EXISTING_PATH:-}', method='${_FEAT_EXISTING_METHOD:-}')."

  __run_feature_hook__ __reinstall_pre

  __reinstall_init__
  __reinstall_run__
  __reinstall_finish__

  __run_feature_hook__ __reinstall_post
}

__reinstall_init__() {
  logging__debug "Starting reinstall initialization."

  __run_feature_hook__ __reinstall_init_pre

  __verify_system_requirements__
  __resolve_input_version__
  __resolve_input_method__
  __ctx_sync_pm_version__
  __resolve_input_prefixes__

  __run_feature_hook__ __reinstall_init_post
}

__reinstall_run__() {
  # Uninstall the existing installation (if any) then perform a fresh install.
  # Called when if_exists=reinstall. _FEAT_EXISTING_PATH is guaranteed non-empty.

  __run_feature_hook__ __reinstall_run_pre

  logging__info "Reinstall: uninstalling existing installation before fresh install."
  __uninstall_run__
  __uninstall_finish__
  __dep_install_base__
  __install_run__
  __install_finish__

  __run_feature_hook__ __reinstall_run_post
}

__reinstall_finish__() {

  __run_feature_hook__ __reinstall_finish_pre

  logging__success "Reinstallation complete."

  __run_feature_hook__ __reinstall_finish_post
}

# Update
# ======

# Returns 0 when the existing installation method requires a migrate-then-reinstall
# before switching to the new METHOD value.
__method_changed__() {
  case "${_FEAT_EXISTING_METHOD:-}" in
    package)          [[ "${METHOD}" != "package" ]] ;;
    upstream-package) [[ "${METHOD}" != "upstream-package" ]] ;;
    npm)              [[ "${METHOD}" != "npm" ]] ;;
    npm-bundled)      [[ "${METHOD}" != "npm-bundled" ]] ;;
    git-clone)        [[ "${METHOD}" != "git-clone" ]] ;;
    prefix)
      case "${METHOD}" in
        package | upstream-package) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    *) return 1 ;;
  esac
}

# Centralised routing step for __update__. Evaluates method, prefix, and version state
# in that order and either handles the update fully (returns 0, caller must not call
# __update_run__) or signals that __update_run__ should proceed (returns 1).
__update_predispatch__() {
  # 1. Method mismatch → migrate: uninstall old, install new.
  if __method_changed__; then
    logging__info "Update predispatch: method changed ('${_FEAT_EXISTING_METHOD:-}' → '${METHOD}'); migrating."
    __update_run_migrate__
    return 0
  fi

  # 2. Prefix check: if a prefix binary is expected but absent, install fresh at the
  #    configured prefix. __install_run__ only writes to ${PREFIX}; any unmanaged binary
  #    at another path (e.g. /usr/bin) is left untouched.
  if [[ -v _RESOLVED_PREFIX && -n "${_FEAT_CONTRACT_PRIMARY_BIN:-}" ]] && __feat_prefix_applies__; then
    local _pfx_bin="${_RESOLVED_PREFIX}/${PREFIX_BIN_DIR}/${_FEAT_CONTRACT_PRIMARY_BIN}"
    if [[ ! -f "${_pfx_bin}" ]]; then
      logging__info "Update predispatch: prefix binary '${_pfx_bin}' missing; installing fresh at prefix."
      __install_run__
      return 0
    fi
    logging__debug "Update predispatch: prefix binary '${_pfx_bin}' present."
  fi

  # 3. Version check: if version already matches, skip __update_run__ entirely.
  #    __install_finish__ still runs to idempotently refresh all shell artifacts.
  if __feat_check_version_match__; then
    logging__info "Update predispatch: version already matches; refreshing shell artifacts only."
    return 0
  fi

  # 4. Prefix ok, version mismatch → proceed to feature-specific __update_run__.
  logging__info "Update predispatch: proceeding to in-place update (METHOD='${METHOD}', VERSION='${VERSION:-}')."
  return 1
}

__update__() {

  logging__info "Starting update (path='${_FEAT_EXISTING_PATH:-}', method='${_FEAT_EXISTING_METHOD:-}', target METHOD='${METHOD:-unset}', VERSION='${VERSION:-unset}')."

  __run_feature_hook__ __update_pre

  __update_init__
  __update_predispatch__ || __update_run__
  __install_finish__
  __update_finish__

  __run_feature_hook__ __update_post
}

__update_init__() {
  logging__debug "Starting update initialization."

  __run_feature_hook__ __update_init_pre

  __verify_system_requirements__
  __resolve_input_version__
  __resolve_input_method__
  __ctx_sync_pm_version__
  __resolve_input_prefixes__
  __dep_install_base__ --update

  __run_feature_hook__ __update_init_post
}

__update_run__() {
  # Apply an in-place version update. Only called by __update__ when __update_predispatch__
  # has already confirmed: method matches, prefix binary exists (if prefix is configured),
  # and version is out of date. Method migration is handled by __update_predispatch__.
  #
  # Same/compatible method — dispatches on METHOD:
  #   package           ospkg__run --update (PM upgrade).
  #   upstream-package  ospkg__run --update against OSPKG_MANIFEST_METHOD_UPSTREAM_PACKAGE_RUN.
  #   binary       __install_run__ (download + overwrite).
  #   cargo        __install_run__ (cargo install upgrades in place).
  #   npm          __install_run__ (npm install -g upgrades).
  #   npm-bundled  __install_run__ (__install_run_npm_bundled__ detects _FEAT_EXISTING_PATH → passes --update).
  #   script       __install_run__ (re-run upstream installer).
  #   source       __install_run__ (compile + overwrite-in-place).
  #   (none)       Error — no auto-implementation.
  #
  # For tools with their own update mechanism (e.g. pixi self-update, rustup
  # update), use __update_run_pre or override __update_run__ entirely.

  __run_feature_hook__ __update_run_pre

  if [[ ! -v METHOD ]]; then
    logging__fatal "Update without METHOD; overwrite __update_run__."
    exit 1
  fi

  logging__install "Applying in-place update via METHOD='${METHOD}'."

  case "${METHOD}" in
    package)
      __update_run_package__
      ;;
    upstream-package)
      __update_run_upstream_package__
      ;;
    git-clone)
      __update_run_git_clone__
      ;;
    *)
      # binary, cargo, npm, npm-bundled, script, source: install path overwrites / upgrades naturally.
      # __install_run_npm_bundled__ detects _FEAT_EXISTING_PATH → passes --update.
      __install_run__
      ;;
  esac

  __run_feature_hook__ __update_run_post
}

__update_run_migrate__() {
  __run_feature_hook__ __update_run_migrate_pre
  logging__info "Installation method changing from '${_FEAT_EXISTING_METHOD}' to '${METHOD}'; uninstalling before reinstalling."
  __uninstall_run__
  __uninstall_finish__
  __install_run__
  __run_feature_hook__ __update_run_migrate_post
}

__update_run_package__() {
  __run_feature_hook__ __update_run_package_pre
  logging__install "Updating package dependencies."
  __dep_install_for_method__ --update
  __run_feature_hook__ __update_run_package_post
}

__update_run_upstream_package__() {
  __run_feature_hook__ __update_run_upstream_package_pre
  logging__install "Updating upstream-package dependencies."
  __dep_install_for_method__ --update
  __run_feature_hook__ __update_run_upstream_package_post
}

__update_run_git_clone__() {
  __run_feature_hook__ __update_run_git_clone_pre
  local _ref_args=()
  [[ -v VERSION && -n "${VERSION}" ]] && _ref_args=(--ref "${VERSION}")
  local _sha_args=()
  [[ -n "${_FEAT_RESOLVED_GIT_SHA:-}" ]] && _sha_args=(--resolved-sha "${_FEAT_RESOLVED_GIT_SHA}")
  logging__install "Updating git-clone at '${_RESOLVED_PREFIX}' (ref='${VERSION:-HEAD}')."
  git__update "${_RESOLVED_PREFIX}" "${_ref_args[@]+"${_ref_args[@]}"}" "${_sha_args[@]+"${_sha_args[@]}"}"
  _git_clone_apply_config "${_RESOLVED_PREFIX}" "${VERSION:-}"
  __run_feature_hook__ __update_run_git_clone_post
}

__update_finish__() {

  __run_feature_hook__ __update_finish_pre

  logging__success "Update complete."

  __run_feature_hook__ __update_finish_post
}

# Finalization
# ============

# Re-entrancy guard for __err__: prevents an infinite ERR trap loop if
# logging__error itself triggers a failure.
__ERR_TRAP_RUNNING=0

__err__() {
  local _rc=$?
  # Capture BASH_COMMAND immediately — some bash versions update it as trap body executes.
  local _failed_cmd="${BASH_COMMAND}"
  # logging__error (from logging.sh) works before and after logging__setup —
  # it buffers to the pending file until the mux is running. The only window
  # where it is unavailable is before __init_lib__ sources the library.
  if ! declare -f logging__error > /dev/null 2>&1; then
    exit "$_rc"
  fi
  (( __ERR_TRAP_RUNNING )) && exit "$_rc"
  __ERR_TRAP_RUNNING=1
  # In bash 4.4+, inside an ERR trap:
  #   BASH_LINENO[0]  — line of the failing command in BASH_SOURCE[1]
  #   FUNCNAME[i]     — call stack (index 0 = __err__ itself; skip it)
  #   BASH_SOURCE[i]  — parallel source-file array
  #   BASH_LINENO[i]  — line in BASH_SOURCE[i+1] where FUNCNAME[i] was called
  # ($LINENO is the current line within __err__, not the failing command — do not use it.)
  local _src _fn _line _trace="" _i
  _src="$(basename "${BASH_SOURCE[1]:-"?"}")"
  _fn="${FUNCNAME[1]:-main}"
  _line="${BASH_LINENO[0]:-?}"
  for (( _i = 1; _i < ${#FUNCNAME[@]}; _i++ )); do
    [[ -n "$_trace" ]] && _trace+=" ← "
    _trace+="${FUNCNAME[$_i]:-main}($(basename "${BASH_SOURCE[$_i]:-?}"):${BASH_LINENO[$((_i - 1))]})"
  done
  logging__error "command failed (exit ${_rc}) at ${_src}:${_line} in ${_fn}: ${_failed_cmd}"
  logging__debug "  stack: ${_trace}"
  exit "$_rc"
}

__exit__() {
  # Capture status before trap - EXIT: `trap -` resets $? to 0.
  local _rc=$?
  trap - EXIT ERR
  set +e

  # Flush pending POSIX-phase messages (logged before logging__setup) to stderr
  # on early exit; no-op once the mux has taken over or already flushed.
  declare -f logging__finalize_parse_buffer > /dev/null 2>&1 && logging__finalize_parse_buffer
  if ! declare -f logging__is_setup > /dev/null 2>&1 || ! logging__is_setup; then
    declare -f file__session_cleanup > /dev/null 2>&1 && file__session_cleanup
    return "$_rc"
  fi

  if [[ $_rc -eq 0 ]]; then
    logging__success "$_FEAT_NAME script finished successfully."
  else
    logging__fatal "$_FEAT_NAME script exited with error ${_rc}."
  fi

  # Define __exit_pre in the hand-written section
  # for feature-specific cleanup (e.g. removing temp files).
  __run_feature_hook__ --warn __exit_pre

  # Build-dependency group cleanup runs FIRST so that, under the ospkg live
  # registry, this invocation deregisters and the last-out decision is computed
  # before the shared, machine-global teardown steps below (cache clean,
  # bootstrap-bash removal) consult ospkg__is_last_out. It is always invoked in
  # non-session mode — even when KEEP_BUILD_DEPS=true — so the invocation still
  # deregisters; the function itself preserves keep semantics (and today's exact
  # behaviour when no registry is active). Session children defer to the session
  # orchestrator's ospkg__cleanup_session_build_groups.
  if [[ -z "${_SYSSET_SESSION_TRACK_DIR:-}" ]]; then
    ospkg__cleanup_all_build_groups "${KEEP_BUILD_DEPS:-false}" || logging__warn "Build-dependency group cleanup failed."
  fi

  # Package-manager cache cleanup is machine-global state: perform it only when
  # this invocation is the registry last-out (ospkg__is_last_out is true without
  # an active registry, so single invocations behave as today).
  if [[ "${KEEP_CACHE}" != true ]] && ospkg__is_last_out; then
    if users__is_privileged || [[ "$(os__kernel)" == "Darwin" ]]; then
      ospkg__clean || logging__warn "Package-manager cache cleanup failed."
    else
      logging__info "Skipping package-manager cache cleanup (no privilege available)."
    fi
  fi

  if [[ "${KEEP_BUILD_DEPS}" != true ]]; then
    ospkg__cleanup_resources || logging__warn "Tracked resource cleanup failed."
  fi
  # Remove a PM-installed bootstrap bash when it is no longer needed. This mutates
  # machine-global package state, so it is gated on the registry last-out decision.
  if [[ "${KEEP_BUILD_DEPS}" != true ]] && [[ -z "${_SYSSET_SESSION_TRACK_DIR:-}" ]] && \
     ospkg__is_last_out && [[ -n "${_BASH_INSTALLED_BY_PM:-}" ]]; then
    case "${_BASH_INSTALLED_BY_PM}" in
      port)
        # port dependents: remove only when nothing else requires bash.
        if ! port dependents bash 2>/dev/null | grep -qv "has no dependents\|^[[:space:]]*$"; then
          logging__remove "Removing PM-installed bootstrap bash via port."
          port uninstall bash 2>/dev/null || logging__warn "port uninstall bash failed."
        else
          logging__skip "Skipping port uninstall of bootstrap bash (other dependents present)."
        fi
        ;;
      nix-env)
        # Nix profiles are isolated — no cascade risk; remove unconditionally.
        logging__remove "Removing PM-installed bootstrap bash via nix-env."
        nix-env --uninstall bash 2>/dev/null || logging__warn "nix-env --uninstall bash failed."
        ;;
      *)
        if [[ "$(ospkg__pm 2>/dev/null)" == "${_BASH_INSTALLED_BY_PM}" ]] && \
           ! ospkg__has_rdeps bash; then
          ospkg__remove_user bash
        fi
        ;;
    esac
  fi

  logging__feature_exit "$_FEAT_NAME v$_FEAT_VERSION"
  logging__cleanup
  file__session_cleanup
  return "$_rc"
}

# Helpers
# =======
__feat_capture_version_input__() {
  # Snapshot user version spec once VERSION is known from argparse.
  # Internal only — not a feature option; never re-assigned elsewhere.
  if [[ -v VERSION ]]; then
    declare -g VERSION_INPUT="${VERSION}"
  fi
}

__ctx_sync_version__() {
  # Mirror version globals → feat.version_input, feat.version, feat.tag.
  if [[ -v VERSION_INPUT ]]; then
    ctx__set feat.version_input="${VERSION_INPUT}"
  fi
  if [[ -v VERSION ]]; then
    ctx__set feat.version="${VERSION:-}"
  fi
  ctx__set feat.tag="${_FEAT_RESOLVED_TAG:-}"
  unset _FEAT_PM_VERSION_SPEC_CACHE
}

__ctx_sync_method__() {
  if [[ -v METHOD ]]; then
    ctx__set feat.method="${METHOD:-}"
  fi
}

__ctx_sync_prefix__() {
  if [[ -v _RESOLVED_PREFIX ]]; then
    ctx__set feat.prefix="${_RESOLVED_PREFIX}"
  else
    ctx__set feat.prefix=""
  fi
}

__ctx_sync__() {
  __ctx_sync_version__
  __ctx_sync_method__
  __ctx_sync_prefix__
}

__ctx_sync_pm_version__() {
  declare -g _FEAT_PM_VERSION_SPEC_CACHE
  _FEAT_PM_VERSION_SPEC_CACHE="$(__feat_pm_version_spec__)"
  ctx__set feat.pm_version="${_FEAT_PM_VERSION_SPEC_CACHE}"
}

__feat_filter_binary_src__() {
  local _line _path _when
  if ! argparse__var_declared BINARY_SRC; then
    return 0
  fi
  for _line in "${BINARY_SRC[@]+"${BINARY_SRC[@]}"}"; do
    [[ -n "${_line}" ]] || continue
    if [[ "${_line}" != *$'\t'* ]]; then
      printf '%s\n' "${_line}"
      continue
    fi
    _path="${_line%%$'\t'*}"
    _when="${_line#*$'\t'}"
    ctx__match_when --quiet "${_when}" && printf '%s\n' "${_path}"
  done
  return 0
}

__feat_filter_source_install_bins__() {
  local _line _path _when
  if ! argparse__var_declared SOURCE_INSTALL_BINS; then
    return 0
  fi
  for _line in "${SOURCE_INSTALL_BINS[@]+"${SOURCE_INSTALL_BINS[@]}"}"; do
    [[ -n "${_line}" ]] || continue
    if [[ "${_line}" != *$'\t'* ]]; then
      printf '%s\n' "${_line}"
      continue
    fi
    _path="${_line%%$'\t'*}"
    _when="${_line#*$'\t'}"
    ctx__match_when --quiet "${_when}" && printf '%s\n' "${_path}"
  done
  return 0
}

__feat_filter_source_build_env__() {
  local _line _value _when
  if ! argparse__var_declared SOURCE_BUILD_ENV; then
    return 0
  fi
  for _line in "${SOURCE_BUILD_ENV[@]+"${SOURCE_BUILD_ENV[@]}"}"; do
    [[ -n "${_line}" ]] || continue
    if [[ "${_line}" != *$'\t'* ]]; then
      printf '%s\n' "${_line}"
      continue
    fi
    _value="${_line%%$'\t'*}"
    _when="${_line#*$'\t'}"
    ctx__match_when --quiet "${_when}" && printf '%s\n' "${_value}"
  done
  return 0
}

__expand_args__() {
  # Expand each element of a source array through ctx__expand_pattern and append results
  # to a destination array. Usage: __expand_args__ <src_var> <dst_var>
  local -n _ea_src="$1" _ea_dst="$2"
  local _ea_e
  for _ea_e in "${_ea_src[@]+"${_ea_src[@]}"}"; do
    _ea_dst+=("$(ctx__expand_pattern "${_ea_e}")")
  done
}

__verify_system_requirements__() {
  __run_feature_hook__ __verify_system_requirements_pre
  ${{ _script.system_requirements_guard }}$
  __run_feature_hook__ __verify_system_requirements_post
}

__feat_check_version_match__() {
  # Sets _FEAT_INSTALLED_VER. Returns 0 when already at the target version
  # (caller should skip), 1 when installation should proceed.
  # Available via __update_run_pre to short-circuit when the installed version
  # already matches the resolved VERSION.
  declare -g _FEAT_INSTALLED_VER=""
  [[ -n "${_FEAT_EXISTING_PATH}" ]] || {
    logging__debug "No existing path; version match check cannot proceed."
    return 1
  }
  [[ -v VERSION && -n "${VERSION}" ]] || {
    logging__debug "VERSION unset; version match check cannot proceed."
    return 1
  }
  if declare -f __installed_version > /dev/null; then
    _FEAT_INSTALLED_VER="$(__installed_version "${_FEAT_EXISTING_PATH}")"
  elif [[ -n "${_FEAT_CONTRACT_PRIMARY_BIN:-}" && -n "${VERSION_FLAG:-}" ]]; then
    _FEAT_INSTALLED_VER="$("${_FEAT_EXISTING_PATH}" "${VERSION_FLAG}" 2>&1 \
      | ver__extract_version || true)"
  fi
  # For git_ref resolution, compare installed HEAD SHA against the remotely resolved SHA.
  # For all other resolution types, _FEAT_RESOLVED_GIT_SHA is empty → falls back to VERSION.
  local _target_ver="${_FEAT_RESOLVED_GIT_SHA:-${VERSION}}"
  if [[ -n "${_FEAT_INSTALLED_VER}" && "${_FEAT_INSTALLED_VER}" == "${_target_ver}" ]]; then
    logging__info "Already at version '${VERSION}' (installed='${_FEAT_INSTALLED_VER}'); skipping."
    return 0
  fi
  logging__info "Version mismatch: installed='${_FEAT_INSTALLED_VER:-unknown}', target='${_target_ver}'; update needed."
  return 1
}

__feat_do_configure_users__() {
  __run_feature_hook__ __feat_do_configure_users_pre
  if ! declare -f __configure_user > /dev/null; then
    logging__skip "__configure_user not defined; skipping user configuration."
    __run_feature_hook__ __feat_do_configure_users_post
    return 0
  fi

  declare -g _FEAT_CONFIGURE_USERS
  local -a _ul_args=()

  [[ -v ADD_CURRENT_USER ]] && _ul_args+=(--current "${ADD_CURRENT_USER}")
  [[ -v ADD_REMOTE_USER ]] && _ul_args+=(--remote "${ADD_REMOTE_USER}")
  [[ -v ADD_CONTAINER_USER ]] && _ul_args+=(--container "${ADD_CONTAINER_USER}")
  if [[ -v ADD_USERS ]]; then
    for _u in "${ADD_USERS[@]+"${ADD_USERS[@]}"}"; do
      _ul_args+=(--user "${_u}")
    done
  fi

  mapfile -t _FEAT_CONFIGURE_USERS < <(users__resolve_list "${_ul_args[@]}")

  if ((${#_FEAT_CONFIGURE_USERS[@]} == 0)); then
    logging__skip "No users resolved for configuration."
  else
    logging__info "Configuring ${#_FEAT_CONFIGURE_USERS[@]} user(s): ${_FEAT_CONFIGURE_USERS[*]}."
  fi

  local _user
  for _user in "${_FEAT_CONFIGURE_USERS[@]+"${_FEAT_CONFIGURE_USERS[@]}"}"; do
    if ! id "${_user}" > /dev/null 2>&1; then
      logging__warn "User '${_user}' not found; skipping configuration."
      continue
    fi
    __run_feature_hook__ --warn __configure_user "${_user}"
  done
  __run_feature_hook__ __feat_do_configure_users_post
  return
}

# Input Resolution
# ================

__feat_is_pm_version_spec__() {
  # Stricter than ver__extract_version --full-match: rejects inline-label strings like "3rd-party".
  local _bare="${1#v}"
  [[ -n "${_bare}" ]] || return 1
  [[ "${_bare}" =~ ^[0-9]+(\.[0-9]+)*(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]
}

__feat_normalize_pm_version_spec__() {
  printf '%s' "${1#v}"
}

__feat_pm_version_resolution_pm_applicable__() {
  case "${VERSION_RESOLUTION:-}" in
    github_release | github_tag | npm | sidecar) return 0 ;;
    *) return 1 ;;
  esac
}

__feat_auto_method_version_channel__() {
  # Channel selector for METHOD=auto PM feasibility checks.
  # Precondition: VERSION_INPUT is set (capture ran or test helper called).
  if [[ -z "${VERSION_INPUT}" ]]; then
    printf 'stable'
    return
  fi
  printf '%s' "${VERSION_INPUT}"
}

__feat_pm_version_spec__() {
  # Print the version spec ospkg should use for PM installs (empty = unversioned).
  #
  # PM channels (stable/latest) → empty (distro default).
  # Semver prefix/exact → VERSION_INPUT (ospkg resolves against PM repos).
  # Opaque/registry specs → resolved VERSION when upstream already resolved;
  #   else lazy registry resolve when VERSION_RESOLUTION supports PM pinning.
  # git_ref and other non-registry types → empty (PM cannot pin by VCS ref).
  if [[ -v _FEAT_PM_VERSION_SPEC_CACHE ]]; then
    printf '%s' "${_FEAT_PM_VERSION_SPEC_CACHE}"
    return 0
  fi
  local _input=""
  [[ -v VERSION_INPUT ]] && _input="${VERSION_INPUT}"
  case "${_input}" in
    '' | stable | latest)
      printf ''
      return 0
      ;;
  esac
  if __feat_is_pm_version_spec__ "${_input}"; then
    __feat_normalize_pm_version_spec__ "${_input}"
    return 0
  fi
  if [[ -n "${VERSION:-}" && "${VERSION}" != "${_input}" ]]; then
    if __feat_is_pm_version_spec__ "${VERSION}"; then
      __feat_normalize_pm_version_spec__ "${VERSION}"
    else
      printf '%s' "${VERSION}"
    fi
    return 0
  fi
  case "${VERSION_RESOLUTION:-}" in
    none | '')
      printf '%s' "${_input}"
      return 0
      ;;
  esac
  if ! __feat_pm_version_resolution_pm_applicable__; then
    logging__debug "VERSION_RESOLUTION='${VERSION_RESOLUTION}' is not used for PM version pinning; installing unversioned."
    printf ''
    return 0
  fi
  local _resolved=""
  if _resolved="$(__feat_resolve_version_spec__ "${_input}")"; then
    printf '%s' "${_resolved}"
    return 0
  fi
  logging__warn "Could not resolve '${_input}' for PM version pin; installing unversioned."
  printf ''
  return 0
}

__feat_resolve_version_spec__() {
  # Resolve <spec> to a bare version string on stdout and in _FEAT_RESOLVE_VERSION_RESULT.
  #
  # Optional --update-globals sets _FEAT_RESOLVED_TAG / _FEAT_RESOLVED_GIT_SHA when
  # applicable (install init). PM-only lazy resolution omits this flag.
  local _spec="${1:-}" _update_globals=false
  shift || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --update-globals)
        _update_globals=true
        shift
        ;;
      *)
        logging__error "__feat_resolve_version_spec__: unknown argument '${1}'."
        return 1
        ;;
    esac
  done
  declare -g _FEAT_RESOLVE_VERSION_RESULT=""
  [[ -n "${_spec}" ]] || return 1

  if declare -f __resolve_version > /dev/null; then
    local _saved_version="${VERSION:-}"
    VERSION="${_spec}"
    _FEAT_RESOLVE_VERSION_RESULT="$(__resolve_version)"
    local _rc=$?
    VERSION="${_saved_version}"
    printf '%s\n' "${_FEAT_RESOLVE_VERSION_RESULT}"
    return "$_rc"
  fi

  case "${VERSION_RESOLUTION:-}" in
    github_release | github_tag)
      if [[ -z "${VERSION_URI:-}" ]]; then
        logging__error "_options.version.resolution=${VERSION_RESOLUTION} requires VERSION_URI to be set in metadata."
        return 1
      fi
      local _endpoint="${VERSION_RESOLUTION#github_}" _both
      logging__info "Resolving GitHub version (URI='${VERSION_URI}', spec='${_spec}', endpoint='${_endpoint}')."
      local _tag_prefix_args=()
      [[ -n "${VERSION_TAG_PREFIX:-}" ]] && _tag_prefix_args=(--tag-prefix "${VERSION_TAG_PREFIX}")
      _both="$(github__resolve_version "${VERSION_URI}" "${_spec}" --endpoint "${_endpoint}" "${_tag_prefix_args[@]+"${_tag_prefix_args[@]}"}")"
      local _rc=$?
      [[ $_rc == 0 ]] || {
        logging__error "failed to resolve GitHub version (URI='${VERSION_URI}', spec='${_spec}')."
        return "$_rc"
      }
      if [[ "${_update_globals}" == true ]]; then
        local _resolved_tag=""
        _resolved_tag="$(printf '%s\n' "${_both}" | head -1)"
        declare -g _FEAT_RESOLVED_TAG="${_resolved_tag}"
      fi
      _FEAT_RESOLVE_VERSION_RESULT="$(printf '%s\n' "${_both}" | tail -1)"
      printf '%s\n' "${_FEAT_RESOLVE_VERSION_RESULT}"
      ;;
    npm)
      if [[ -z "${VERSION_URI:-}" ]]; then
        logging__error "_options.version.resolution=npm requires VERSION_URI to be set in metadata."
        return 1
      fi
      logging__info "Resolving npm version (URI='${VERSION_URI}', spec='${_spec}')."
      _FEAT_RESOLVE_VERSION_RESULT="$(npm__resolve_version_uri "${VERSION_URI}" "${_spec}")"
      local _rc=$?
      [[ $_rc == 0 ]] || {
        logging__error "failed to resolve npm version (URI='${VERSION_URI}', spec='${_spec}')."
        return "$_rc"
      }
      printf '%s\n' "${_FEAT_RESOLVE_VERSION_RESULT}"
      ;;
    cargo)
      if [[ -z "${VERSION_URI:-}" ]]; then
        logging__error "_options.version.resolution=cargo requires VERSION_URI to be set in metadata."
        return 1
      fi
      logging__info "Resolving cargo version (URI='${VERSION_URI}', spec='${_spec}')."
      _FEAT_RESOLVE_VERSION_RESULT="$(cargo__resolve_version_uri "${VERSION_URI}" "${_spec}")"
      local _rc=$?
      [[ $_rc == 0 ]] || {
        logging__error "failed to resolve cargo version (URI='${VERSION_URI}', spec='${_spec}')."
        return "$_rc"
      }
      printf '%s\n' "${_FEAT_RESOLVE_VERSION_RESULT}"
      ;;
    git_ref)
      if [[ -z "${GIT_CLONE_URI:-}" ]]; then
        logging__error "VERSION_RESOLUTION=git_ref requires GIT_CLONE_URI to be set."
        return 1
      fi
      if [[ "${_update_globals}" == true ]]; then
        logging__install "Bootstrapping git for VERSION_RESOLUTION=git_ref."
        bootstrap__git
        __ctx_sync_version__
        local _git_ref_uri _resolved
        _git_ref_uri="$(ctx__expand_pattern "${GIT_CLONE_URI}")"
        _resolved="$(git__resolve_ref "${_git_ref_uri}" "${_spec}")"
        local _rc=$?
        [[ $_rc == 0 ]] || {
          logging__error "failed to resolve git ref '${_spec}' on '${_git_ref_uri}'."
          return "$_rc"
        }
        declare -g _FEAT_RESOLVED_GIT_SHA="${_resolved}"
      fi
      _FEAT_RESOLVE_VERSION_RESULT="${_spec}"
      printf '%s\n' "${_FEAT_RESOLVE_VERSION_RESULT}"
      ;;
    sidecar)
      if [[ -z "${VERSION_URI:-}" || -z "${VERSION_PATTERN:-}" ]]; then
        logging__error "VERSION_RESOLUTION=sidecar requires VERSION_URI and VERSION_PATTERN to be set in metadata."
        return 1
      fi
      logging__info "Resolving version from sidecar (URI='${VERSION_URI}', spec='${_spec}')."
      _FEAT_RESOLVE_VERSION_RESULT="$(ver__resolve_from_sidecar "${VERSION_URI}" "${VERSION_PATTERN}" "${_spec}")"
      local _rc=$?
      [[ $_rc == 0 ]] || {
        logging__error "failed to resolve sidecar version (URI='${VERSION_URI}', spec='${_spec}')."
        return "$_rc"
      }
      printf '%s\n' "${_FEAT_RESOLVE_VERSION_RESULT}"
      ;;
    none | '')
      logging__skip "VERSION_RESOLUTION unset or 'none'; using spec '${_spec}' as-is."
      _FEAT_RESOLVE_VERSION_RESULT="${_spec}"
      printf '%s\n' "${_FEAT_RESOLVE_VERSION_RESULT}"
      ;;
    *)
      logging__error "_options.version.resolution='${VERSION_RESOLUTION}' has no auto-implementation; define __resolve_version to handle it."
      return 1
      ;;
  esac
}

__resolve_auto_method__() {
  # Centralized METHOD=auto resolver driven by _FEAT_CONTRACT_* variables.
  # Iterates methods in priority order, evaluating feasibility for each.
  # Prints the first feasible method name and returns 0, or returns 1 if none found.
  local _arch _kernel _privileged _triple _pkg_query
  _arch="$(os__release_arch 2>/dev/null)" || _arch=""
  _kernel="$(os__release_kernel 2>/dev/null)" || _kernel=""
  _triple="$(os__rust_triple 2>/dev/null)" || _triple=""
  _privileged=false
  users__is_privileged 2>/dev/null && _privileged=true
  # OS package name for PM feasibility/version checks: registers_as when set,
  # otherwise the primary binary name (same as the binary when names match).
  _pkg_query="${REGISTER_PACKAGE_NAME:-${_FEAT_CONTRACT_PRIMARY_BIN}}"

  local _method
  for _method in binary upstream-package package script npm-bundled npm cargo source git-clone; do
    [[ " ${_FEAT_CONTRACT_METHODS} " == *" ${_method} "* ]] || continue

    case "${_method}" in
      binary)
        if [[ "${BINARY_ASSET_URI:-}" == *'{plat.rust_triple}'* ]]; then
          [[ -n "${_triple}" ]] || continue
        fi
        ctx__match_when --quiet "${_FEAT_CONTRACT_BINARY_WHEN}" || {
          local _rc=$?
          [[ $_rc -eq 2 ]] && {
            logging__error "When-condition evaluation failed for method '${_method}'."
            return 1
          }
          continue
        }
        ;;
      upstream-package)
        [[ "${_kernel}" != "linux" ]] || [[ "${_privileged}" == "true" ]] || continue
        # Only for stable when version is semver-resolved: upstream repos aren't
        # queryable before setup and won't track pre-releases or specific versions.
        # VERSION_RESOLUTION=none means VERSION is a custom opaque string; treat as stable.
        if [[ "${VERSION_RESOLUTION:-}" != "none" ]]; then
          [[ -v VERSION_INPUT ]] || logging__fatal "VERSION_INPUT unset during auto-method channel check"
          case "$(__feat_auto_method_version_channel__)" in stable) : ;; *) continue ;; esac
        fi
        ctx__match_when --quiet "${_FEAT_CONTRACT_UPSTREAM_PKG_WHEN}" || {
          local _rc=$?
          [[ $_rc -eq 2 ]] && {
            logging__error "When-condition evaluation failed for method '${_method}'."
            return 1
          }
          continue
        }
        ;;
      package)
        [[ "${_kernel}" != "linux" ]] || [[ "${_privileged}" == "true" ]] || continue
        # stable → PM always viable; latest → skip (PM won't have very latest);
        # specific version → check PM with derived feat.pm_version spec (ospkg prefix matching).
        # VERSION_RESOLUTION=none means VERSION is a custom opaque string; always viable.
        if [[ "${VERSION_RESOLUTION:-}" != "none" ]]; then
          [[ -v VERSION_INPUT ]] || logging__fatal "VERSION_INPUT unset during auto-method channel check"
          case "$(__feat_auto_method_version_channel__)" in
            stable) : ;;
            latest) continue ;;
            *)
              local _pm_spec=""
              _pm_spec="$(__feat_pm_version_spec__)"
              [[ -n "${_pm_spec}" ]] || continue
              ospkg__has_available_version "${_pkg_query}" "${_pm_spec}" 2>/dev/null || continue
              ;;
          esac
        fi
        ctx__match_when --quiet "${_FEAT_CONTRACT_PACKAGE_WHEN}" || {
          local _rc=$?
          [[ $_rc -eq 2 ]] && {
            logging__error "When-condition evaluation failed for method '${_method}'."
            return 1
          }
          continue
        }
        ;;
      script | source) : ;;
      npm-bundled)
        [[ " linux darwin " == *" ${_kernel} "* ]] || continue
        [[ " amd64 arm64 " == *" ${_arch} "* ]] || continue
        [[ "$(os__platform 2>/dev/null)" != "alpine" ]] || continue
        ;;
      npm) command -v npm > /dev/null 2>&1 || continue ;;
      cargo) command -v cargo > /dev/null 2>&1 || continue ;;
      git-clone) command -v git > /dev/null 2>&1 || continue ;;
    esac

    printf '%s\n' "${_method}"
    return 0
  done

  logging__error "No feasible method found for METHOD=auto (available: ${_FEAT_CONTRACT_METHODS:-none})."
  return 1
}

__resolve_input_method__() {
  # Resolves METHOD=auto to a concrete value.
  # Priority: __resolve_method hook (feature escape hatch) → __resolve_auto_method__
  # (driven by _FEAT_CONTRACT_* metadata). No-op when METHOD is already concrete.
  [[ -v METHOD && "${METHOD}" == "auto" ]] || {
    logging__debug "METHOD already concrete ('${METHOD:-unset}'); skipping auto-resolution."
    # Auto-register installed-version probe for git-clone when not overridden by the feature.
    if [[ "${METHOD:-}" == "git-clone" ]] && ! declare -f __installed_version > /dev/null; then
      __installed_version() {
        local _p="${1:-${_RESOLVED_PREFIX}}"
        [[ -d "${_p}/.git" ]] && git__head_sha "${_p}" 2>/dev/null || printf ''
      }
    fi
    __ctx_sync_method__
    return 0
  }
  if declare -f __resolve_method > /dev/null; then
    logging__debug "Executing feature hook '__resolve_method'."
    METHOD="$(__resolve_method)"
    local _rc=$?
    if [[ $_rc == 0 ]]; then
      logging__debug "Feature hook '__resolve_method' executed successfully."
    else
      logging__error "Feature hook '__resolve_method' failed."
      return "$_rc"
    fi
  elif [[ -n "${_FEAT_CONTRACT_METHODS}" ]]; then
    logging__debug "Executing centralized '__resolve_auto_method__'."
    METHOD="$(__resolve_auto_method__)"
    local _rc=$?
    if [[ $_rc != 0 ]]; then
      return "$_rc"
    fi
  else
    logging__error "METHOD=auto but no methods declared (_FEAT_CONTRACT_METHODS is empty)."
    return 1
  fi
  logging__info "Resolved METHOD=auto → '${METHOD}'."
  __ctx_sync_method__
  # Auto-register installed-version probe for git-clone when resolved to git-clone.
  if [[ "${METHOD:-}" == "git-clone" ]] && ! declare -f __installed_version > /dev/null; then
    __installed_version() {
      local _p="${1:-${_RESOLVED_PREFIX}}"
      [[ -d "${_p}/.git" ]] && git__head_sha "${_p}" 2>/dev/null || printf ''
    }
  fi
}

__resolve_input_version__() {
  # Translate the user-visible version spec ("stable", "1.2", "latest", …) into
  # a concrete version string that can be compared against what is already
  # installed and used in download URL patterns.
  #
  # _FEAT_RESOLVED_TAG is always reset to "" at entry so downstream steps can
  # reference it unconditionally regardless of which path was taken.
  #
  # Early exits (no resolution performed, returns 0):
  #  - VERSION is not declared or is empty — the feature has no version option.
  #  - METHOD=package — the OS package manager controls which version is
  #    installed; a version spec would be silently ignored by the package
  #    manager anyway, so resolution is skipped entirely.
  #  - METHOD=upstream-package — the upstream OS repository controls which
  #    version is installed; VERSION is passed as-is to the manifest (e.g.
  #    "stable" and "latest" are channel selectors, not concrete versions).
  #
  # Resolution runs before __resolve_input_method__ so METHOD=auto can evaluate
  # version constraints in method `when` blocks (e.g. binary only for older releases).
  #
  # Hook: __resolve_version
  #   Provide this when none of the standard resolution types fits — e.g. a
  #   proprietary registry, a version file fetched from a repo, or any logic
  #   that requires custom shell code.  The hook receives the user's raw spec
  #   in $VERSION and must print the resolved concrete version string on stdout;
  #   the orchestrator captures that output and writes it back to VERSION.  The
  #   hook must not modify VERSION directly.
  #
  # Auto-implementations (when no hook is defined, keyed by
  # _options.version.resolution in metadata):
  #
  #   github_release  Resolves against the GitHub Releases API (--endpoint
  #                   release) via VERSION_URI.  Handles "stable", "latest",
  #                   and semver-prefix specs.  Sets _FEAT_RESOLVED_TAG to the
  #                   full release tag (e.g. "v1.7.1") so the binary download
  #                   step can use the exact resolved tag without reconstructing
  #                   it.  Requires VERSION_URI to be the API base URL.
  #
  #   github_tag      Same as github_release but queries the git tags API
  #                   (--endpoint tag), for repos that publish lightweight tags
  #                   without formal GitHub Releases.  Also sets
  #                   _FEAT_RESOLVED_TAG.  Requires VERSION_URI.
  #
  #   npm             Resolves against the npm registry via VERSION_URI using
  #                   npm__resolve_version_uri.  _FEAT_RESOLVED_TAG is left
  #                   empty (npm installs are addressed by version, not tag).
  #                   Requires VERSION_URI to be the registry package URL.
  #
  #   cargo           Resolves against the crates.io registry via VERSION_URI
  #                   using cargo__resolve_version_uri.  _FEAT_RESOLVED_TAG is
  #                   left empty (cargo installs are addressed by version, not
  #                   tag).  Requires VERSION_URI to be the crates.io crate URL.
  #
  #   none / ""       VERSION is already a concrete value; no network resolution
  #                   is needed.  A silent no-op.
  #
  #   anything else   Error — no auto-implementation exists for this type.
  #                   Define _feat_resolve_version to handle it.
  #
  # Globals written:
  #   VERSION             Concrete resolved version string (e.g. "1.7.1").
  #   VERSION_INPUT       User's raw version spec (captured at argparse in
  #                       __feat_capture_version_input__); unchanged here.
  #   _FEAT_RESOLVED_TAG  Full release or git tag when resolved via GitHub
  #                       (e.g. "v1.7.1", "jq-1.7.1"); empty string otherwise.
  __run_feature_hook__ __resolve_input_version_pre

  declare -g _FEAT_RESOLVED_TAG=""
  declare -g _FEAT_RESOLVED_GIT_SHA=""
  __ctx_sync_version__
  if ! { [[ -v VERSION && -n "${VERSION}" ]] && [[ ! -v METHOD || "${METHOD}" != "package" && "${METHOD}" != "upstream-package" ]]; }; then
    if [[ ! -v VERSION || -z "${VERSION}" ]]; then
      logging__skip "VERSION unset; skipping version resolution."
    elif [[ "${METHOD:-}" == "upstream-package" ]]; then
      logging__skip "METHOD=upstream-package; skipping version resolution (package manager controls version)."
    else
      logging__skip "METHOD=package; skipping version resolution (package manager controls version)."
    fi
    __run_feature_hook__ __resolve_input_version_post
    __ctx_sync_version__
    return 0
  fi

  if declare -f __resolve_version > /dev/null; then
    logging__debug "Executing feature hook '__resolve_version'."
    logging__info "Resolving version via '__resolve_version' hook (spec='${VERSION:-}')."
    VERSION="$(__resolve_version)"
    local _rc=$?
    if [[ $_rc == 0 ]]; then
      logging__debug "Feature hook '__resolve_version' executed successfully."
    else
      logging__error "Feature hook '__resolve_version' failed."
      return "$_rc"
    fi
  else
    local _version_spec="${VERSION:-}"
    logging__info "Resolving version (resolution='${VERSION_RESOLUTION:-none}', spec='${_version_spec}')."
    __feat_resolve_version_spec__ "${_version_spec}" --update-globals
    local _rc=$?
    [[ $_rc == 0 ]] || {
      logging__error "failed to resolve version spec '${_version_spec}'."
      return "$_rc"
    }
    VERSION="${_FEAT_RESOLVE_VERSION_RESULT:-}"
    if [[ "${VERSION_RESOLUTION:-}" == git_ref && -n "${_FEAT_RESOLVED_GIT_SHA:-}" &&
      "${_FEAT_RESOLVED_GIT_SHA}" == "${_version_spec}" ]]; then
      logging__info "Ref '${_version_spec}' not found as a named ref on remote; treating as SHA."
    fi
  fi
  if [[ -n "${_FEAT_RESOLVED_TAG}" ]]; then
    logging__info "Resolved version: '${VERSION}' (tag: '${_FEAT_RESOLVED_TAG}')."
  elif [[ -n "${_FEAT_RESOLVED_GIT_SHA}" ]]; then
    logging__info "Resolved version: '${VERSION}' (SHA: '${_FEAT_RESOLVED_GIT_SHA}')."
  else
    logging__info "Resolved version: '${VERSION}'."
  fi

  __run_feature_hook__ __resolve_input_version_post
  __ctx_sync_version__
}

__resolve_input_prefixes__() {
  __run_feature_hook__ __resolve_input_prefixes_pre
  __resolve_prefix__
  __run_feature_hook__ __resolve_input_prefixes_post
  return
}

# shellcheck disable=SC2329,SC2317
__resolve_prefix__() {
  argparse__var_declared PREFIX || {
    logging__skip "PREFIX option unset; skipping prefix resolution."
    return 0
  }
  local _eff_user="${INSTALL_USER:-$(users__get_current)}"
  local _symlink_user
  _symlink_user="$(users__get_current)"

  if [[ -v _RESOLVED_PREFIX ]]; then
    logging__skip "PREFIX already resolved to '${_RESOLVED_PREFIX}'; skipping."
    return 0
  fi

  if ((${#PREFIX[@]} == 0)); then
    logging__error "Option 'prefix' is empty; omit the option or provide at least one prefix candidate group."
    logging__fatal "Exiting with status 1 (empty prefix)."
    exit 1
  fi

  local -a _fwp_args=()
  local _elem _when _paths _expanded
  for _elem in "${PREFIX[@]}"; do
    [[ -n "${_elem}" ]] || continue
    _when=""
    _paths="${_elem}"
    if [[ "${_elem}" == *:* && "${_elem}" =~ ^([^/][^[:space:]]*([[:space:]]+[^/][^[:space:]]*)*)[[:space:]]+(\/.*|~.*|\$\{.*)$ ]]; then
      _when="${BASH_REMATCH[1]}"
      _when="${_when%"${_when##*[![:space:]]}"}"
      _paths="${BASH_REMATCH[3]}"
    fi
    _expanded="$(users__expand_path --user "$_eff_user" "${_paths}")"
    _fwp_args+=(--)
    [[ -n "${_when}" ]] && _fwp_args+=("${_when}")
    # shellcheck disable=SC2206
    _fwp_args+=(${_expanded})
  done
  declare -g _RESOLVED_PREFIX
  _RESOLVED_PREFIX="$(users__first_writeable_path "${_fwp_args[@]}")"

  users__can_write "${_RESOLVED_PREFIX}" || {
    logging__error "Option 'prefix': '${_RESOLVED_PREFIX}' is not writable."
    logging__fatal "Exiting with status 1 (prefix not writable)."
    exit 1
  }
  PREFIX_SCOPE="$(users__is_user_path "${_RESOLVED_PREFIX}" && printf user || printf system)"
  logging__info "Option 'prefix' resolved to '${_RESOLVED_PREFIX}'."

  if [[ -v RUNTIME_PATH ]]; then
    if [[ "$RUNTIME_PATH" != *'$'* && "$RUNTIME_PATH" != *'~'* ]] || id "$_eff_user" &>/dev/null; then
      declare -g _RESOLVED_RUNTIME_PATH
      _RESOLVED_RUNTIME_PATH="$(users__expand_path --user "$_eff_user" "$RUNTIME_PATH")"
      logging__info "Option 'runtime_path' resolved to '${_RESOLVED_RUNTIME_PATH}'."
    else
      logging__info "Option 'runtime_path' not resolved: install user '${_eff_user}' does not exist yet."
    fi
  fi

  if [[ -v PREFIX_SYMLINK_NONROOT ]]; then
    PREFIX_SYMLINK_NONROOT="$(users__expand_path --user "$_symlink_user" "$PREFIX_SYMLINK_NONROOT")"
    logging__info "Option 'prefix_symlink_nonroot' resolved to '${PREFIX_SYMLINK_NONROOT}'."
  fi
  if argparse__var_declared PREFIX_SYMLINKS; then
    local -a _sl=()
    for _elem in "${PREFIX_SYMLINKS[@]}"; do
      _sl+=("$(users__expand_path --user "$_symlink_user" "$_elem")")
    done
    PREFIX_SYMLINKS=("${_sl[@]}")
  fi
  if argparse__var_declared PREFIX_EXPORTS; then
    local -a _ex=()
    for _elem in "${PREFIX_EXPORTS[@]}"; do
      _ex+=("$(users__expand_path --user "$_symlink_user" "$_elem")")
    done
    PREFIX_EXPORTS=("${_ex[@]}")
  fi

  __ctx_sync_prefix__
  return
}

# Dependency Installation
# =======================

__dep_normalize_manifest_value__() {
  # Expand literal \n escapes (some devcontainer build args serialize multiline strings this way).
  local _var="$1"
  local _val="${!_var}"
  if [[ -n "$_val" && "$_val" != *$'\n'* && "$_val" == *'\n'* ]]; then
    printf -v "$_var" '%b' "$_val"
    logging__info "Expanded literal \\n escapes in ${_var} value."
  fi
}

__dep_manifest_var_set__() {
  # True when a manifest option variable is set (env, CLI, or default). Prefer [[ -v ]]
  # over argparse__var_declared: the latter can miss variables inherited from the environment.
  [[ -v "$1" ]]
}

__dep_fetch_extra_args__() {
  # shellcheck disable=SC2178
  local -n _out="$1"
  _out=()
  [[ -n "${FETCH_NETRC:-}" ]] && _out+=(--fetch-netrc-file "$FETCH_NETRC")
  if argparse__var_declared FETCH_HEADERS && ((${#FETCH_HEADERS[@]} > 0)); then
    local _osh
    for _osh in "${FETCH_HEADERS[@]}"; do
      _out+=(--fetch-header "$_osh")
    done
  fi
}

__dep_method_env_var__() {
  local _lifecycle="$1"
  local _method="${2:-${METHOD:-}}"
  local _m_key="${_method//-/_}"
  printf 'OSPKG_MANIFEST_METHOD_%s_%s\n' "${_m_key^^}" "${_lifecycle^^}"
}

__dep_option_env_var__() {
  local _name="$1"
  printf 'OSPKG_MANIFEST_OPTION_%s\n' "${_name^^}"
}

__dep_install_from_env__() {
  local _var="$1"
  local _lifecycle="$2"
  local _label="${3:-${_var}}"
  shift 3

  __dep_normalize_manifest_value__ "$_var"
  local _manifest="${!_var}"
  [[ -n "$_manifest" ]] || {
    logging__skip "No manifest in '${_var}'; skipping."
    return 0
  }

  if ! users__is_privileged && [[ "$(os__kernel)" == "Linux" ]]; then
    logging__warn "Skipping '${_label}' (${_lifecycle}) dependency installation (no privilege available); ensure dependencies are pre-installed."
    return 0
  fi

  logging__install "Installing '${_label}' (${_lifecycle}) dependencies from '${_var}'."

  local -a _args=(--manifest "$_manifest")
  [[ "$_lifecycle" == build ]] && _args+=(--build-group "${_SYSSET_BUILD_CONTEXT}::method-${METHOD:-unknown}")
  local -a _fetch_args=()
  __dep_fetch_extra_args__ _fetch_args
  _args+=("${_fetch_args[@]+"${_fetch_args[@]}"}")
  ospkg__run "${_args[@]}" "$@"
}

__dep_uninstall_from_env__() {
  local _var="$1"
  local _lifecycle="$2"
  local _label="${3:-${_var}}"
  shift 3

  __dep_normalize_manifest_value__ "$_var"
  local _manifest="${!_var}"
  [[ -n "$_manifest" ]] || {
    logging__skip "No manifest in '${_var}'; skipping uninstall."
    return 0
  }

  logging__remove "Uninstalling '${_label}' (${_lifecycle}) dependencies from '${_var}'."
  local -a _args=(--manifest "$_manifest" --remove)
  local -a _fetch_args=()
  __dep_fetch_extra_args__ _fetch_args
  _args+=("${_fetch_args[@]+"${_fetch_args[@]}"}")
  ospkg__run "${_args[@]}" "$@"
}

__dep_install_base__() {
  local _lc _var
  for _lc in build run; do
    _var="OSPKG_MANIFEST_BASE_${_lc^^}"
    if __dep_manifest_var_set__ "$_var"; then
      __dep_install_from_env__ "$_var" "$_lc" "base" "$@"
    fi
  done
  return 0
}

__dep_install_for_method__() {
  [[ -v METHOD ]] || return 0
  local _lc _var
  for _lc in build run; do
    _var="$(__dep_method_env_var__ "$_lc")"
    if ! __dep_manifest_var_set__ "$_var"; then
      continue
    fi
    if [[ "$_lc" == build ]] && ! users__is_privileged && [[ "$(os__kernel)" == "Linux" ]]; then
      logging__info "Non-privileged install: skipping method-${METHOD} build deps; expecting pre-installed."
      continue
    fi
    if [[ "$_lc" == run && "${METHOD}" == upstream-package ]]; then
      if [[ -v KEEP_REPOS && "${KEEP_REPOS}" == true ]]; then
        __dep_install_from_env__ "$_var" "$_lc" "method-${METHOD}" --keep_repos "$@"
      else
        __dep_install_from_env__ "$_var" "$_lc" "method-${METHOD}" "$@"
      fi
    else
      __dep_install_from_env__ "$_var" "$_lc" "method-${METHOD}" "$@"
    fi
  done
}

__dep_uninstall_for_method__() {
  local _method="$1"
  local _lc _var _m_saved="${METHOD:-}"
  METHOD="$_method"
  for _lc in build run; do
    _var="$(__dep_method_env_var__ "$_lc" "$_method")"
    if __dep_manifest_var_set__ "$_var"; then
      __dep_uninstall_from_env__ "$_var" "$_lc" "method-${_method}"
    fi
  done
  METHOD="$_m_saved"
}

__dep_install_option_bound__() {
  [[ -n "${_FEAT_DEP_TRIGGER_SPECS:-}" ]] || return 0

  local _opt _mvar _bvar _installed=0 _trigger_rows=0
  while IFS=$'\t' read -r _opt _mvar _bvar; do
    [[ -n "$_opt" ]] || continue
    ((_trigger_rows++)) || true
    [[ "${!_bvar:-false}" == true ]] || continue
    __dep_install_from_env__ "$_mvar" run "$_opt" "$@" && _installed=1
  done <<< "${_FEAT_DEP_TRIGGER_SPECS}"

  if [[ "$_installed" -eq 0 && "$_trigger_rows" -gt 1 ]]; then
    logging__skip "No bundles selected; nothing to install."
  fi
  return 0
}

__dep_uninstall_option_bound__() {
  [[ -n "${_FEAT_DEP_TRIGGER_SPECS:-}" ]] || return 0

  local _opt _mvar _bvar _removed=0
  while IFS=$'\t' read -r _opt _mvar _bvar; do
    [[ -n "$_opt" ]] || continue
    [[ "${!_bvar:-false}" == true ]] || continue
    __dep_uninstall_from_env__ "$_mvar" run "$_opt" && _removed=1
  done <<< "${_FEAT_DEP_TRIGGER_SPECS}"

  if [[ "$_removed" -eq 0 ]]; then
    logging__skip "No bundles selected; nothing to uninstall."
  fi
  return 0
}

__dep_install_option__() {
  local _name="$1"
  shift
  local _mvar
  _mvar="$(__dep_option_env_var__ "$_name")"
  if ! __dep_manifest_var_set__ "$_mvar"; then
    logging__skip "No manifest option 'ospkg_manifest_option_${_name}'; skipping."
    return 0
  fi
  __dep_install_from_env__ "$_mvar" run "option-${_name}" "$@"
}

# Self-Copy Deployment
# =====================

__deploy_self__() {
  # Copy this feature's installer (install.sh, install.bash), shared lib, and
  # any bundled files/schemas to a persistent share directory, so that
  # lifecycle hook scripts and entrypoints — which run long after the build
  # tarball is gone — can call back into a full, working copy of the feature
  # with complete DevFeats lib access.
  #
  # Lifecycle scripts must invoke the copy via `sh install.sh` (the POSIX
  # entrypoint), never `bash install.bash` directly: install.sh is what
  # bootstraps a compatible bash if the target system doesn't already have
  # one, and is the same conventional entrypoint used for the original
  # (build-time) invocation.
  #
  # Also copies any `*.schema.json` files found directly in ${_FEAT_DIR} (not
  # recursively), so `_jsonschema` argparse validation — which resolves schema
  # paths relative to ${_FEAT_DIR} — keeps working when ${_FEAT_DIR} becomes
  # this persistent copy at lifecycle time.
  #
  # Idempotent: guarded by `[ -d "${_FEAT_SHARE_DIR_ROOT}" ]` so it only runs
  # once — at lifecycle time the directory already exists and this is a no-op.
  #
  # Call explicitly from a feature's __install_run__ (or equivalent) when the
  # feature needs this pattern; not called automatically by the template.
  if [[ -d "${_FEAT_SHARE_DIR_ROOT}" ]]; then
    logging__skip "Self-copy already deployed at '${_FEAT_SHARE_DIR_ROOT}'; skipping."
    return 0
  fi
  logging__install "Deploying self-copy to '${_FEAT_SHARE_DIR_ROOT}'."
  file__mkdir "${_FEAT_SHARE_DIR_ROOT}"
  file__cp "${_FEAT_DIR}/install.sh" "${_FEAT_SHARE_DIR_ROOT}/install.sh"
  file__cp "${_FEAT_DIR}/install.bash" "${_FEAT_SHARE_DIR_ROOT}/install.bash"
  file__chmod +x "${_FEAT_SHARE_DIR_ROOT}/install.sh"
  file__cp -r "${_FEAT_DIR}/lib" "${_FEAT_SHARE_DIR_ROOT}/"
  if [[ -d "${_FEAT_FILES_DIR}" ]]; then
    file__cp -r "${_FEAT_FILES_DIR}" "${_FEAT_SHARE_DIR_ROOT}/"
  fi
  local _schema
  for _schema in "${_FEAT_DIR}"/*.schema.json; do
    [[ -f "${_schema}" ]] || continue
    file__cp "${_schema}" "${_FEAT_SHARE_DIR_ROOT}/$(basename "${_schema}")"
  done
  logging__success "Self-copy deployed to '${_FEAT_SHARE_DIR_ROOT}'."
}

# Lifecycle Script Deployment
# ============================

__deploy_lifecycle_scripts__() {
  local _is_skip=""
  [[ "${1:-}" == "--skip" ]] && _is_skip=1
  os__is_devcontainer_build || {
    logging__skip "Not a devcontainer build; skipping lifecycle script deployment."
    return 0
  }

  logging__info "Deploying lifecycle scripts to '${_FEAT_LIFECYCLE_DIR}'."
  local _lc_dir_ready=""

  if [[ -d "${_FEAT_FILES_DIR}" ]]; then
    local -A _lc_prefix_map=(
      ["on-create--"]="${_FEAT_LIFECYCLE_ON_CREATE}"
      ["update-content--"]="${_FEAT_LIFECYCLE_UPDATE_CONTENT}"
      ["post-create--"]="${_FEAT_LIFECYCLE_POST_CREATE}"
      ["post-start--"]="${_FEAT_LIFECYCLE_POST_START}"
      ["post-attach--"]="${_FEAT_LIFECYCLE_POST_ATTACH}"
    )

    local _boilerplate
    _boilerplate=$(
      cat << 'BOILERPLATE'
#!/bin/sh
set -e
warn() { printf '[%s] WARN: %s\n' "$(basename "$0")" "$*" >&2; }
_CONF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0").conf"
if [ -f "$_CONF" ]; then
  . "$_CONF"
fi
if [ -n "${_SKIP:-}" ]; then
  printf '[%s] Installation skipped; this hook is a no-op.\n' "$(basename "$0")" >&2
  exit 0
fi
BOILERPLATE
    )

    local _f _base _prefix _dest
    for _f in "${_FEAT_FILES_DIR}"/*.sh; do
      [[ -f "${_f}" ]] || continue
      _base="${_f##*/}"
      _dest=""

      if [[ "${_base}" == "entrypoint.sh" ]]; then
        [[ -n "${_lc_dir_ready}" ]] || { file__mkdir "${_FEAT_LIFECYCLE_DIR}"; _lc_dir_ready=1; }
        __deploy_lifecycle_script__ "${_f}" "${_FEAT_ENTRYPOINT_PATH}" "${_boilerplate}"
        _dest="${_FEAT_ENTRYPOINT_PATH}"
      else
        for _prefix in "${!_lc_prefix_map[@]}"; do
          if [[ "${_base}" == "${_prefix}"*.sh ]]; then
            local _task="${_base#"${_prefix}"}"
            _task="${_task%.sh}"
            _dest="${_lc_prefix_map[${_prefix}]}${_task}.sh"
            [[ -n "${_lc_dir_ready}" ]] || { file__mkdir "${_FEAT_LIFECYCLE_DIR}"; _lc_dir_ready=1; }
            __deploy_lifecycle_script__ "${_f}" "${_dest}" "${_boilerplate}"
            break
          fi
        done
      fi

      [[ -n "${_dest}" ]] || continue

      if [[ -n "${_is_skip}" ]] || [[ -v "_FEAT_LIFECYCLE_CONF_VARS[${_base}]" ]]; then
        local _varnames _vname
        _varnames="${_FEAT_LIFECYCLE_CONF_VARS["${_base}"]:-}"
        {
          [[ -n "${_is_skip}" ]] && printf '_SKIP=1\n'
          for _vname in ${_varnames}; do
            [[ -v "${_vname}" ]] && printf '%s="%s"\n' "${_vname}" "${!_vname//\"/\\\"}"
          done
        } > "${_dest}.conf"
      fi
    done
  fi

  if [[ -v INSTALL_VERIFICATION_ARGS ]]; then
    [[ -n "${_lc_dir_ready}" ]] || { file__mkdir "${_FEAT_LIFECYCLE_DIR}"; _lc_dir_ready=1; }
    if [[ -n "${_is_skip}" ]] || [[ -z "${INSTALL_VERIFICATION_ARGS}" ]]; then
      logging__skip "Writing verification no-op script to '${_FEAT_LIFECYCLE_POST_CREATE}verification.sh'."
      {
        cat << 'VERIFY_NOOP'
#!/bin/sh
printf '[verification] Verification skipped; this hook is a no-op.\n' >&2
VERIFY_NOOP
      } > "${_FEAT_LIFECYCLE_POST_CREATE}verification.sh"
    else
      local _vcmd="${_FEAT_VERIFY_CMD:-${_DF_EXPECTED_CMD:-${_FEAT_CONTRACT_PRIMARY_BIN}}}"
      # When verify.cmd names a declared prefix bin, prefer the discovery-
      # resolved command (_DF_EXPECTED_CMD): under prefix_discovery=none that's
      # the full prefix path, whereas the bare verify.cmd name isn't on PATH in
      # the non-login postCreate shell and would fail with 127. verify.cmd stays
      # authoritative for prefix-less features (no _DF_EXPECTED_CMD).
      if [[ -n "${_FEAT_VERIFY_CMD:-}" && -n "${_DF_EXPECTED_CMD:-}" && -v PREFIX_BINS ]]; then
        local _pb
        for _pb in "${PREFIX_BINS[@]}"; do
          [[ "${_pb}" == "${_FEAT_VERIFY_CMD}" ]] && {
            _vcmd="${_DF_EXPECTED_CMD}"
            break
          }
        done
      fi
      if [[ -z "${_vcmd}" ]]; then
        logging__error "Cannot write verification script — _DF_EXPECTED_CMD is empty and _options.verify.cmd is not set. Declare _options.verify.cmd or add _options.prefix.bins."
        return 1
      fi
      logging__install "Writing verification script to '${_FEAT_LIFECYCLE_POST_CREATE}verification.sh' (cmd='${_vcmd}')."
      printf '#!/bin/sh\nset -x\n"%s" %s\n' "${_vcmd}" "${INSTALL_VERIFICATION_ARGS}" \
        > "${_FEAT_LIFECYCLE_POST_CREATE}verification.sh"
    fi
    file__chmod +x "${_FEAT_LIFECYCLE_POST_CREATE}verification.sh"
  fi
}

__deploy_lifecycle_script__() {
  # Write _src to _dest with the boilerplate prepended.
  # The boilerplate owns the shebang (#!/bin/sh) and set -e; any shebang
  # in the source file is stripped, as it exists only for local tooling.
  local _src="$1" _dest="$2" _boilerplate="$3"
  logging__install "Deploying lifecycle script '${_src}' → '${_dest}'."
  local _first_line=""
  read -r _first_line < "${_src}" || true
  {
    printf '%s\n' "${_boilerplate}"
    if [[ "${_first_line}" == '#!'* ]]; then
      tail -n +2 "${_src}"
    else
      cat "${_src}"
    fi
  } > "${_dest}"
  file__chmod +x "${_dest}"
  if ! sh -n "${_dest}" 2>&1; then
    logging__error "Lifecycle script '${_dest}' failed syntax check (sh -n)."
    return 1
  fi
}

# Feature Functions
# =================
${{ _script.feature_functions }}$

__main__ "$@"

# =============================================================================
# FEATURE HOOK CONTRACT
# =============================================================================
#
# CUSTOMIZATION MECHANISMS (in order of preference)
# --------------------------------------------------
#
# 1. _pre / _post hooks — inject code before/after any template function.
#    Every template function foo() checks for __foo_pre and __foo_post at its
#    entry and exit. Define them in install.bash to run custom logic around the
#    auto-implementation without replacing it.
#
#    Available pre/post pairs (all optional):
#      __install_pre / __install_post
#      __install_init_pre / __install_init_post
#      __install_run_pre / __install_run_post
#      __install_run_binary_pre / __install_run_binary_post
#      __install_run_package_pre / __install_run_package_post
#      __install_run_script_pre / __install_run_script_post
#      __install_run_source_pre / __install_run_source_post
#      __install_run_cargo_pre / __install_run_cargo_post
#      __install_run_npm_pre / __install_run_npm_post
#      __install_finish_pre / __install_finish_post
#      __uninstall_pre / __uninstall_post
#      __uninstall_init_pre / __uninstall_init_post
#      __uninstall_run_pre / __uninstall_run_post
#      __uninstall_run_prefix_pre / __uninstall_run_prefix_post
#      __uninstall_run_npm_pre / __uninstall_run_npm_post
#      __uninstall_run_npm_bundled_pre / __uninstall_run_npm_bundled_post
#      __uninstall_run_package_pre / __uninstall_run_package_post
#      __uninstall_finish_pre / __uninstall_finish_post
#      __reinstall_pre / __reinstall_post
#      __reinstall_init_pre / __reinstall_init_post
#      __reinstall_run_pre / __reinstall_run_post
#      __reinstall_finish_pre / __reinstall_finish_post
#      __update_pre / __update_post
#      __update_init_pre / __update_init_post
#      __update_run_pre / __update_run_post
#      __update_run_migrate_pre / __update_run_migrate_post
#      __update_run_package_pre / __update_run_package_post
#      __update_finish_pre / __update_finish_post
#      __verify_system_requirements_pre / __verify_system_requirements_post
#      __feat_do_configure_users_pre / __feat_do_configure_users_post
#      __resolve_input_version_pre / __resolve_input_version_post
#      __resolve_input_prefixes_pre / __resolve_input_prefixes_post
#      __exit_pre  (no post; runs in the trap handler)
#
# 2. Data arrays — set in a _pre hook to influence the auto-implementation.
#    _FEAT_INSTALL_SCRIPT_ARGS  (array) — extra args appended to the installer
#      script invocation in __install_run_script__. Set in
#      __install_run_script_pre. (For static args, set _options.method.script.args
#      in metadata instead.)
#    _FEAT_CARGO_COMMAND        (array) — overrides the cargo command, e.g.
#      (cargo binstall). Defaults to (cargo install) or (cargo binstall) when
#      cargo-binstall is on PATH. Set in __install_run_cargo_pre.
#    _FEAT_CARGO_INSTALL_ARGS   (array) — extra args appended after the
#      standard --root / --version / CARGO_INSTALL_ARGS args in
#      __install_run_cargo__. Set in __install_run_cargo_pre.
#      (For static args, set _options.method.cargo.args in metadata instead.)
#
# 3. Function override — redefine any template function in install.bash.
#    Feature functions are injected after all template definitions, so a
#    feature-defined __install_run_binary__() completely replaces the
#    template's version. Use this as a last resort when neither _pre/_post
#    hooks nor data arrays are sufficient.
#
# DISPATCHED HOOKS (called via declare -f at runtime)
# ----------------------------------------------------
# __resolve_method()
#   Optional escape hatch when METHOD=auto. Stdout: one concrete method name.
#   Called by __resolve_input_method__ before the shared __resolve_auto_method__.
#   Only define this when the shared auto resolver is insufficient.
#
# __resolve_version()
#   Called by __resolve_input_version__ when VERSION is set and METHOD!=package.
#   Stdout: resolved bare version (e.g. "1.2.3").
#   May also set _FEAT_RESOLVED_TAG via declare -g for full tag access.
#   Auto-impl: github__resolve_version when _options.version.resolution is set.
#
# __installed_version <installed_path>
#   Called by __feat_check_version_match__ to probe the installed version.
#   Stdout: installed version string.
#   Auto-impl: "${path}" "${VERSION_FLAG}" | ver__extract_version
#
# __install_run_script_run <script_path>
#   Called by __install_run_script__ after fetching the script URL, when
#   METHOD=script and this hook is defined. Receives the downloaded script
#   path. Use when you need full control over how the script is invoked.
#   If absent, the script is run directly with the static args from
#   _options.method.script.args and any _FEAT_INSTALL_SCRIPT_ARGS.
#
# __install_run_source_build <src_dir>
#   Called by __install_run_source__ after download+extraction.
#   Receives the path to the top-level extracted source directory.
#   Use for platform-specific flags, multi-pass builds, or custom install steps
#   that cannot be expressed declaratively with SOURCE_BUILD_SYSTEM /
#   SOURCE_CONFIGURE_ARGS / SOURCE_CMAKE_ARGS / SOURCE_BUILD_ENV / SOURCE_MAKE_FLAGS /
#   SOURCE_MAKE_TARGETS / SOURCE_INSTALL_BINS.
#   When absent, __install_run_source_auto_build__ is invoked instead
#   (driven by SOURCE_BUILD_SYSTEM / SOURCE_CONFIGURE_ARGS / SOURCE_CMAKE_ARGS /
#   SOURCE_BUILD_ENV / SOURCE_MAKE_FLAGS / SOURCE_MAKE_TARGETS,
#   followed by __install_run_source_auto_install_bins__ when SOURCE_INSTALL_BINS is non-empty after when-filtering).
#
# __get_completion_content__ <shell>
#   Called by __install_shell_completions__ to produce completion text for one
#   shell. Stdout: completion script. Return non-zero to skip that shell.
#   Auto-impl: run `${PREFIX}/bin/<PRIMARY_BIN> ${SHELL_COMPLETIONS_CMD} <shell>`
#   when SHELL_COMPLETIONS_CMD is set, or cat the path from SHELL_COMPLETIONS_FILES
#   matching <shell> when set.
#   Only needed when neither auto-impl applies (e.g. bespoke generation logic).
#
# __configure_user <username>
#   Called per resolved user by __feat_do_configure_users__. No auto-impl.
#   __feat_do_configure_users__ must be called explicitly (e.g. from
#   __install_finish_post) to trigger user configuration.
#
# CONTRACT GLOBALS (declare -g; set by orchestrators, readable in hooks)
# -----------------------------------------------------------------------
# _FEAT_EXISTING_PATH    Path to the detected existing binary, or "".
# _FEAT_EXISTING_METHOD  Install method of the existing binary, or "".
#                        Values: "package", "npm", "npm-bundled", "prefix", "".
# _FEAT_INSTALLED_VER    Installed version string from __feat_check_version_match__.
# _FEAT_RESOLVED_TAG     Full VCS tag from version resolution (e.g. "v1.7.1").
# _FEAT_CONFIGURE_USERS  Array of usernames resolved by __feat_do_configure_users__.
#
# MIGRATION PATTERN
# -----------------
# 1. In metadata.yaml: replace options.version / options.method with
#    _options.version / _options.method contract data.
# 2. In install.bash: define only the hooks needed. All module-level code
#    must become hook functions; the template's __main__ drives execution.
#
# Example — install-shellcheck:
#
#   # metadata.yaml adds:
#   _options:
#     gh_repo: koalaman/shellcheck
#     version:
#       resolution: github_release
#       default: stable
#       inputs: [stable, latest, semver]
#     method:
#       binary:
#         asset_pattern: "shellcheck-v{feat.version}.{plat.kernel:lower}.{plat.machine}.tar.xz"
#         binary_src:
#           - shellcheck
#       package: {}
#
#   # install.bash (only hook needed):
#   __resolve_method() {
#     if [[ "$(os__release_kernel)" == "darwin" && "$(os__arch)" == "arm64" ]]; then
#       printf 'package\n'
#     else
#       printf 'binary\n'
#     fi
#   }
# =============================================================================
