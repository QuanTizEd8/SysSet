# shellcheck shell=bash

__install_run__() {
  logging__install "Running install-os-pkg (install_self='${INSTALL_SELF}', lifecycle_hook='${LIFECYCLE_HOOK:-}')."
  if [[ -z "$MANIFEST" && "$INSTALL_SELF" != true ]]; then
    logging__error "'MANIFEST' is required when 'install_self' is false."
    return 1
  fi
  # At this point MANIFEST is either:
  #   - a local file path (resolved by _content_or_uri argparse step from inline
  #     content, a remote URI, or an existing local file)
  #   - a non-existing local path (workspace-mounted file, available at hook time)
  # Schema validation already ran in the argparse _jsonschema step; any violation
  # would have exited before reaching here.

  if [[ -n "$LIFECYCLE_HOOK" ]]; then
    if [[ -z "$MANIFEST" ]]; then
      logging__error "'manifest' is required when 'lifecycle_hook' is set."
      return 1
    fi
  fi

  if ! [[ "$LISTS_MAX_AGE" =~ ^[0-9]+$ ]]; then
    logging__error "Invalid lists_max_age value: '$LISTS_MAX_AGE'. Must be a non-negative integer."
    return 1
  fi

  # Always deploy the self-copy so lifecycle hook scripts can call back into a
  # full, working copy of the feature (with DevFeats lib access) later. The
  # user-visible wrapper script (/usr/local/bin/install-os-pkg) is optional
  # and only written when install_self=true.
  __deploy_self__

  if [[ "$INSTALL_SELF" == true ]]; then
    local _BIN="/usr/local/bin/install-os-pkg"
    if [ ! -x "$_BIN" ]; then
      printf '#!/bin/sh\nexec sh "%s/install.sh" "$@"\n' "${_FEAT_SHARE_DIR_ROOT}" | file__tee "$_BIN"
      file__chmod +x "$_BIN"
      logging__success "Installed system command: $_BIN"
    fi
  else
    logging__skip "install_self=false; skipping system command installation."
  fi

  # When lifecycle_hook is set, write a hook script and exit without installing.
  if [[ -n "$LIFECYCLE_HOOK" ]]; then
    local _HOOK_OPTS
    local _HOOK_DIR="${_FEAT_LIFECYCLE_DIR}"
    file__mkdir "$_HOOK_DIR"
    local _MANIFEST_ARG="$MANIFEST"
    # MANIFEST may point to a session-scoped temp file (inline content or remote URI
    # resolved by argparse).  Copy it to a persistent location so the hook script
    # can read it after this process exits and the session temp dir is cleaned up.
    if [[ -f "$MANIFEST" ]]; then
      file__cp "$MANIFEST" "$_HOOK_DIR/manifest.yaml"
      _MANIFEST_ARG="$_HOOK_DIR/manifest.yaml"
      logging__info "Copied resolved manifest to '$_MANIFEST_ARG'."
    fi
    _HOOK_OPTS="--manifest $(printf '%q' "$_MANIFEST_ARG")"
    [[ -n "${FETCH_NETRC:-}" ]] && _HOOK_OPTS+=" --fetch-netrc-file $(printf '%q' "$FETCH_NETRC")"
    if [[ ${#FETCH_HEADERS[@]} -gt 0 ]]; then
      local _osh
      for _osh in "${FETCH_HEADERS[@]}"; do
        [[ -n "${_osh}" ]] && _HOOK_OPTS+=" --fetch-header $(printf '%q' "$_osh")"
      done
    fi
    [[ -n "${LOG_LEVEL:-}" ]] && _HOOK_OPTS+=" --log_level $(printf '%q' "$LOG_LEVEL")"
    [[ -n "${LOG_FILE_LEVEL:-}" ]] && _HOOK_OPTS+=" --log_file_level $(printf '%q' "$LOG_FILE_LEVEL")"
    [[ "$INTERACTIVE" == true ]] && _HOOK_OPTS+=" --interactive true"
    [[ "$KEEP_REPOS" == true ]] && _HOOK_OPTS+=" --keep_repos true"
    [[ -n "$LOG_FILE" ]] && _HOOK_OPTS+=" --log_file $(printf '%q' "$LOG_FILE")"
    [[ "$UPDATE" == false ]] && _HOOK_OPTS+=" --update-index false"
    _HOOK_OPTS+=" --lists_max_age $LISTS_MAX_AGE"
    [[ "$DRY_RUN" == true ]] && _HOOK_OPTS+=" --dry_run true"
    [[ "$PREFER_LINUXBREW" == true ]] && _HOOK_OPTS+=" --prefer_linuxbrew true"
    _HOOK_OPTS+=" --keep_cache $KEEP_CACHE"
    local _HOOK_FILE
    case "$LIFECYCLE_HOOK" in
      onCreate) _HOOK_FILE="${_FEAT_LIFECYCLE_ON_CREATE}install.sh" ;;
      updateContent) _HOOK_FILE="${_FEAT_LIFECYCLE_UPDATE_CONTENT}install.sh" ;;
      postCreate) _HOOK_FILE="${_FEAT_LIFECYCLE_POST_CREATE}install.sh" ;;
    esac
    printf '#!/bin/sh\nset -e\nexec sh "%s" %s\n' \
      "${_FEAT_SHARE_DIR_ROOT}/install.sh" "$_HOOK_OPTS" | file__tee "$_HOOK_FILE"
    file__chmod +x "$_HOOK_FILE"
    logging__success "Registered lifecycle hook '$LIFECYCLE_HOOK': $_HOOK_FILE"
    return 0
  fi

  local -a _OSPKG_ARGS=()
  [[ -n "$MANIFEST" ]] && _OSPKG_ARGS+=(--manifest "$MANIFEST")
  [[ -n "${FETCH_NETRC:-}" ]] && _OSPKG_ARGS+=(--fetch-netrc-file "$FETCH_NETRC")
  if [[ ${#FETCH_HEADERS[@]} -gt 0 ]]; then
    local _osh
    for _osh in "${FETCH_HEADERS[@]}"; do
      [[ -n "${_osh}" ]] && _OSPKG_ARGS+=(--fetch-header "$_osh")
    done
  fi
  [[ "$UPDATE" == false ]] && _OSPKG_ARGS+=(--update-index false)

  [[ "$KEEP_REPOS" == true ]] && _OSPKG_ARGS+=(--keep_repos)
  _OSPKG_ARGS+=(--lists_max_age "$LISTS_MAX_AGE")
  [[ "$DRY_RUN" == true ]] && _OSPKG_ARGS+=(--dry_run)
  [[ "$PREFER_LINUXBREW" == true ]] && _OSPKG_ARGS+=(--prefer_linuxbrew)
  [[ "$INTERACTIVE" == true ]] && _OSPKG_ARGS+=(--interactive)
  case "${IF_EXISTS}" in
    update) _OSPKG_ARGS+=(--update) ;;
    fail) _OSPKG_ARGS+=(--fail-if-installed) ;;
  esac
  logging__install "Running package installation via ospkg__run."
  ospkg__run "${_OSPKG_ARGS[@]}"
}

__if_exists_dispatch__() {
  case "${IF_EXISTS}" in
    uninstall) __uninstall_run__ ;;
    reinstall)
      __uninstall_run__
      __install__
      ;;
    *) __install__ ;;
  esac
}

__uninstall_run__() {
  if [[ -z "$MANIFEST" ]]; then
    logging__error "'manifest' is required for if_exists=uninstall/reinstall."
    return 1
  fi
  local -a _args=(--remove --manifest "$MANIFEST")
  [[ -n "${FETCH_NETRC:-}" ]] && _args+=(--fetch-netrc-file "$FETCH_NETRC")
  if [[ ${#FETCH_HEADERS[@]} -gt 0 ]]; then
    local _osh
    for _osh in "${FETCH_HEADERS[@]}"; do
      [[ -n "${_osh}" ]] && _args+=(--fetch-header "$_osh")
    done
  fi
  logging__remove "Uninstalling packages from manifest."
  ospkg__run "${_args[@]}"
}
