# shellcheck shell=bash
# Do not edit _lib/ copies directly — edit lib/ instead.

_install__sanitize_key() {
  # @brief _install__sanitize_key <raw> — Convert arbitrary tool/group identifiers to safe lowercase key fragments.
  local _raw="${1-}"
  _raw="${_raw,,}"
  _raw="${_raw//\//_}"
  _raw="${_raw//[^a-z0-9._-]/_}"
  printf '%s\n' "$_raw"
}

install__state_dir() {
  # @brief install__state_dir — Print installer state directory path under `_FILE__SESSION_ROOT` (creates it if missing).
  file__tmpdir "install-state"
}

install__state_file() {
  # @brief install__state_file <tool> — Print state file path for a tool key.
  local _tool="${1-}" _key
  _key="$(_install__sanitize_key "$_tool")"
  printf '%s/%s.state\n' "$(install__state_dir)" "$_key"
}

install__state_context() {
  # @brief install__state_context <tool> — Read `context` field from tool state file.
  local _tool="${1-}" _f _ctx
  _f="$(install__state_file "$_tool")"
  [[ -f "$_f" ]] || return 1
  _ctx="$(sed -n 's/^context=//p' "$_f" | head -n1)"
  [[ -n "$_ctx" ]] || return 1
  printf '%s\n' "$_ctx"
}

install__state_install_path() {
  # @brief install__state_install_path <tool> — Read `install_path` field from tool state file.
  local _tool="${1-}" _f _p
  _f="$(install__state_file "$_tool")"
  [[ -f "$_f" ]] || return 1
  _p="$(sed -n 's/^install_path=//p' "$_f" | head -n1)"
  [[ -n "$_p" ]] || return 1
  printf '%s\n' "$_p"
}

install__state_owner_group() {
  # @brief install__state_owner_group <tool> — Read `owner_group` field from tool state file.
  local _tool="${1-}" _f _g
  _f="$(install__state_file "$_tool")"
  [[ -f "$_f" ]] || return 1
  _g="$(sed -n 's/^owner_group=//p' "$_f" | head -n1)"
  [[ -n "$_g" ]] || return 1
  printf '%s\n' "$_g"
}

install__state_record() {
  # @brief install__state_record <tool> <context> <method> <install_path> <owner_group> — Persist ownership metadata for a tool install.
  local _tool="${1-}" _context="${2-}" _method="${3-}" _install_path="${4-}" _owner_group="${5-}"
  local _f
  [[ -n "$_tool" && -n "$_context" ]] || {
    logging__error "tool and context are required."
    return 1
  }
  _f="$(install__state_file "$_tool")"
  cat > "$_f" << EOF
tool=${_tool}
context=${_context}
method=${_method}
install_path=${_install_path}
owner_group=${_owner_group}
created_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2> /dev/null || true)
EOF
  [[ -f "$_f" ]] || {
    logging__error "failed to write state file '${_f}' for tool '${_tool}'."
    return 1
  }
  logging__debug "Recorded install state for '${_tool}' (context='${_context}', path='${_install_path}')."
  return 0
}

install__copy_bin() {
  # @brief install__copy_bin <src> <dest> — Copy a binary to `<dest>` with executable permissions (0755), creating parent directories as needed.
  #
  # Uses `install` (coreutils) when available for an atomic copy+mode operation;
  # falls back to `cp` + `chmod` otherwise. Both `cp` and `chmod` are POSIX
  # mandated and available on any bare OS, so no package bootstrapping is needed.
  #
  # Args:
  #   <src>   Path to the source binary.
  #   <dest>  Destination file path (not a directory).
  #
  # Returns: 0 on success, 1 on failure.
  local _src="$1" _dest="$2"
  mkdir -p "$(dirname "$_dest")" || {
    logging__error "failed to create directory '$(dirname "$_dest")'."
    return 1
  }
  logging__install "Installing binary '${_src}' to '${_dest}'."
  local _rc=0
  if command -v install > /dev/null 2>&1; then
    install -m 0755 "$_src" "$_dest" || _rc=$?
  else
    cp "$_src" "$_dest" && chmod 0755 "$_dest" || _rc=$?
  fi
  if ((_rc != 0)); then
    logging__error "failed to install '${_src}' to '${_dest}'."
    return 1
  fi
  return 0
}

install__read_state() {
  # @brief install__read_state <tool> <ctx_var> <path_var> <group_var> — Read all three installation-state fields into caller-named variables in a single call.
  #
  # Each field is populated from the state file written by `install__state_record`.
  # Fields absent from the state file (missing file or missing key) are set to
  # empty strings. Uses `printf -v` so no extra subshell is spawned per field.
  #
  # Args:
  #   <tool>       Tool name key (same value passed to `install__state_record`).
  #   <ctx_var>    Name of the variable to receive the `context` field.
  #   <path_var>   Name of the variable to receive the `install_path` field.
  #   <group_var>  Name of the variable to receive the `owner_group` field.
  local _tool="$1" _ctx_var="$2" _path_var="$3" _group_var="$4"
  printf -v "$_ctx_var" '%s' "$(install__state_context "$_tool" 2> /dev/null || true)"
  printf -v "$_path_var" '%s' "$(install__state_install_path "$_tool" 2> /dev/null || true)"
  printf -v "$_group_var" '%s' "$(install__state_owner_group "$_tool" 2> /dev/null || true)"
}

install__parse_common_opts() {
  # @brief install__parse_common_opts <caller> <ctx_v> <ver_v> <method_v> <prefix_v> <ife_v> <repos_v> <group_v> <idir_v> <ghrepo_v> <extra_arr_v> "$@" — Parse standard install-module flags into caller-named variables.
  #
  # Recognised flags (each takes one value argument):
  #   --context, --version, --method, --prefix, --if-exists,
  #   --repos-manifest, --owner-group, --installer-dir, --gh-repo
  #
  # Unknown flags are appended (with their following value token) to the array
  # variable named by <extra_arr_v>.  Pass "" for <extra_arr_v> to make unknown
  # flags a fatal error (logged under <caller>).
  #
  # Callers must initialise variables to their defaults before calling this
  # function; only flags that are present on the command line are written.
  #
  # Args:
  #   <caller>       Function name used in error messages.
  #   <ctx_v>        Variable name for --context.
  #   <ver_v>        Variable name for --version.
  #   <method_v>     Variable name for --method.
  #   <prefix_v>     Variable name for --prefix.
  #   <ife_v>        Variable name for --if-exists.
  #   <repos_v>      Variable name for --repos-manifest.
  #   <group_v>      Variable name for --owner-group.
  #   <idir_v>       Variable name for --installer-dir.
  #   <ghrepo_v>     Variable name for --gh-repo.
  #   <extra_arr_v>  Array variable name for unrecognised flags (or "" to error).
  #   "$@"           Remaining positional args from the caller.
  #
  # Returns: 0 on success, 1 on unrecognised flag when <extra_arr_v> is "".
  local _caller="$1" _pctx="$2" _pver="$3" _pmethod="$4" _pprefix="$5"
  local _pife="$6" _prepos="$7" _pgroup="$8" _pidir="$9" _pghrepo="${10-}" _pextra="${11-}"
  shift 11
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --context)
        shift
        printf -v "$_pctx" '%s' "${1-}"
        ;;
      --version)
        shift
        printf -v "$_pver" '%s' "${1-}"
        ;;
      --method)
        shift
        printf -v "$_pmethod" '%s' "${1-}"
        ;;
      --prefix)
        shift
        printf -v "$_pprefix" '%s' "${1-}"
        ;;
      --if-exists)
        shift
        printf -v "$_pife" '%s' "${1-}"
        ;;
      --repos-manifest)
        shift
        printf -v "$_prepos" '%s' "${1-}"
        ;;
      --owner-group)
        shift
        printf -v "$_pgroup" '%s' "${1-}"
        ;;
      --installer-dir)
        shift
        printf -v "$_pidir" '%s' "${1-}"
        ;;
      --gh-repo)
        shift
        [[ -n "$_pghrepo" ]] && printf -v "$_pghrepo" '%s' "${1-}"
        ;;
      *)
        if [[ -n "$_pextra" ]]; then
          eval "${_pextra}+=($(printf '%q' "$1"))"
        else
          logging__error "unknown option '$1'"
          return 1
        fi
        ;;
    esac
    shift
  done
}

install__build_release_args() {
  # @brief install__build_release_args <context> <group> <installer_dir> <out_owner_group_arr> <out_idir_arr> — Build the `--owner-group` and `--installer-dir` argument arrays for `github__install_release`.
  #
  # Populates the array variables named by <out_owner_group_arr> and <out_idir_arr>:
  #   --owner-group <group>      added when context == "internal"
  #   --installer-dir <dir>      added when installer_dir is non-empty
  #
  # Args:
  #   <context>           "internal" or "user".
  #   <group>             Resource-tracking group ID.
  #   <installer_dir>     Optional persistent work directory (may be empty).
  #   <out_owner_group_arr>  Name of the caller's array variable for --owner-group args.
  #   <out_idir_arr>         Name of the caller's array variable for --installer-dir args.
  local _context="$1" _group="$2" _installer_dir="$3"
  # shellcheck disable=SC2178
  local -n _bra_og="$4" _bra_id="$5"
  _bra_og=()
  _bra_id=()
  [[ "$_context" == "internal" ]] && _bra_og=(--owner-group "$_group")
  [[ -n "$_installer_dir" ]] && _bra_id=(--installer-dir "$_installer_dir")
}

install__maybe_promote_to_user() {
  # @brief install__maybe_promote_to_user <tool> <context> <method> <owner_group> <existing> <state_ctx_var> <state_path_var> <state_group_var> — Promote an internal install to user-owned when context==user and recorded state==internal.
  #
  # If the conditions are met: untracks the artifact from cleanup, re-records it
  # as user-owned, and sets the caller's state_ctx variable to "user".  A no-op
  # when the conditions are not met.
  #
  # Args:
  #   <tool>            Tool name key (e.g. "jq").
  #   <context>         Caller's requested context ("internal" or "user").
  #   <method>          Install method string recorded in the state file.
  #   <owner_group>     Fallback owner-group when the state file has none.
  #   <existing>        Path to the existing binary (empty → always a no-op).
  #   <state_ctx_var>   Name of caller's variable holding the recorded context.
  #   <state_path_var>  Name of caller's variable holding the recorded install path.
  #   <state_group_var> Name of caller's variable holding the recorded owner group.
  local _tool="$1" _context="$2" _method="$3" _owner_group="$4" _existing="$5"
  local _ctx_var="$6" _path_var="$7" _group_var="$8"
  local _state_ctx="${!_ctx_var}" _state_path="${!_path_var}" _state_group="${!_group_var}"
  [[ -n "$_existing" && "$_context" == "user" && "$_state_ctx" == "internal" ]] || return 0
  install__promote_path_to_user "${_state_group:-$_owner_group}" "$_state_path"
  install__state_record "$_tool" "user" "${_method}" "${_existing}" "$_owner_group" || true
  printf -v "$_ctx_var" '%s' "user"
}

install__track_internal_path() {
  # @brief install__track_internal_path <group-id> <path> — Register internal non-PM artifact path for cleanup via ospkg resource tracking.
  local _group="${1-}" _path="${2-}"
  [[ -n "$_group" && -n "$_path" ]] || return 0
  command -v ospkg__track_resource > /dev/null 2>&1 || return 0
  ospkg__track_resource "$_group" "$_path" || true
  return 0
}

install__promote_path_to_user() {
  # @brief install__promote_path_to_user <group-id> <path> — Remove a previously tracked internal artifact path from cleanup tracking.
  local _group="${1-}" _path="${2-}"
  [[ -n "$_path" ]] || return 0
  command -v ospkg__untrack_resource > /dev/null 2>&1 || return 0
  ospkg__untrack_resource "$_group" "$_path" || true
  return 0
}

install__release_asset() {
  # @brief install__release_asset OPTIONS — Download and install a release asset from any URI.
  #
  # Generalised release-asset installer. Accepts a fully expanded asset URI and
  # delegates download, verification, extraction, and installation to
  # `uri__fetch_asset`.  GitHub Releases API digest lookup is the caller's
  # responsibility (see `github__release_json_digest_from_uri`).
  #
  # Automatic behaviour (when applicable):
  #   - **Sidecar auto-probe**: when neither `--sidecar` nor `--sha256` is given,
  #     three candidate URLs are probed in order:
  #     `<asset-uri>.sha256`, `<release-base>/SHA256SUMS`,
  #     `<release-base>/sha256sum.txt` (where release-base is the asset URI with
  #     the basename stripped).
  #
  # Args:
  #   --asset-uri <uri>          Full asset URI; runtime patterns already expanded.
  #                              Required.
  #   --asset-name <name>        Explicit asset basename override (default: basename
  #                              of --asset-uri with query parameters stripped).
  #   --sidecar <uri>            Explicit sidecar URI (skips auto-probe). A bare
  #                              name (no ://) is prepended with the release base.
  #   --sha256 <hash|none>       Expected SHA-256 hex or 'none' to suppress all
  #                              digest checks.
  #   --binary-src <path>        Repeatable; passed to uri__fetch_asset.
  #   --binary-dest <path>       Repeatable; passed to uri__fetch_asset.
  #   --file-src <path>          Repeatable; passed to uri__fetch_asset.
  #   --file-dest <path>         Repeatable; passed to uri__fetch_asset.
  #   --header <h>               Repeatable; passed to uri__fetch_asset.
  #   --netrc-file <path>        Passed to uri__fetch_asset.
  #   --filename <name>          Passed to uri__fetch_asset.
  #   --owner-group <group>      Passed to uri__fetch_asset.
  #   --installer-dir <dir>      Passed to uri__fetch_asset.
  #   --gpg-key <uri>            Passed to uri__fetch_asset.
  #   --gpg-sig <uri>            Passed to uri__fetch_asset.
  #   --sidecar-gpg-key <uri>    Passed to uri__fetch_asset.
  #   --sidecar-gpg-sig <uri>    Passed to uri__fetch_asset.
  #   --retry <n>                Passed to uri__fetch_asset.
  #   --chmod-exec <spec>        Passed to uri__fetch_asset.
  #
  # Returns: 0 on success, 1 on failure.
  local _asset_uri="" _asset_name_override=""
  local _caller_sha256="" _caller_sha256_set=false
  local _caller_sidecar="" _caller_sidecar_set=false
  local _nbsrc=0 _nbdest=0
  local -a _passthrough=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --asset-uri)
        _asset_uri="$2"
        shift 2
        ;;
      --asset-name)
        _asset_name_override="$2"
        shift 2
        ;;
      --sha256)
        _caller_sha256="$2"
        _caller_sha256_set=true
        _passthrough+=(--sha256 "$2")
        shift 2
        ;;
      --sidecar)
        _caller_sidecar_set=true
        _caller_sidecar="$2"
        shift 2
        ;;
      --binary-src)
        _nbsrc=$((_nbsrc + 1))
        _passthrough+=("$1" "$2")
        shift 2
        ;;
      --binary-dest)
        _nbdest=$((_nbdest + 1))
        _passthrough+=("$1" "$2")
        shift 2
        ;;
      --file-src | --file-dest | \
        --header | --netrc-file | --filename | --owner-group | \
        --installer-dir | --gpg-key | --gpg-sig | \
        --sidecar-gpg-key | --sidecar-gpg-sig | --retry | --chmod-exec)
        _passthrough+=("$1" "$2")
        shift 2
        ;;
      *)
        logging__error "unknown option: '$1'"
        return 1
        ;;
    esac
  done

  [[ -n "$_asset_uri" ]] || {
    logging__error "--asset-uri is required."
    return 1
  }

  if "$_caller_sha256_set" && [[ "$_caller_sha256" != "none" ]]; then
    [[ "$_caller_sha256" =~ ^[0-9a-fA-F]{64}$ ]] || {
      logging__error "--sha256 accepts a 64-char hex or 'none', got '${_caller_sha256}'."
      return 1
    }
  fi
  [[ "$_nbsrc" -gt 0 && "$_nbdest" -gt 1 && "$_nbsrc" -ne "$_nbdest" ]] && {
    logging__error "${_nbsrc} --binary-src but ${_nbdest} --binary-dest (must be equal or use 1 --binary-dest for all)."
    return 1
  }

  # Derive asset name (basename of URI with query params stripped).
  local _asset_name
  if [[ -n "$_asset_name_override" ]]; then
    _asset_name="$_asset_name_override"
  else
    local _uri_stripped="${_asset_uri%%\?*}"
    _asset_name="${_uri_stripped##*/}"
  fi

  # Derive release base for sidecar auto-probe (asset URI with basename stripped).
  local _uri_no_query="${_asset_uri%%\?*}"
  local _release_base="${_uri_no_query%/*}"

  # Resolve explicit sidecar (relative name → prepend release base).
  if "$_caller_sidecar_set"; then
    if [[ "${_caller_sidecar}" != *://* ]]; then
      _passthrough+=(--sidecar "${_release_base}/${_caller_sidecar}")
    else
      _passthrough+=(--sidecar "${_caller_sidecar}")
    fi
  fi

  # ── Sidecar auto-probe (skip if caller passed --sidecar or --sha256 none) ───
  local -a _sidecar_arg=() _probe_auth=()
  local _i=0
  while [[ "$_i" -lt "${#_passthrough[@]}" ]]; do
    case "${_passthrough[$_i]}" in
      --header | --netrc-file)
        _probe_auth+=("${_passthrough[$_i]}" "${_passthrough[$((_i + 1))]}")
        _i=$((_i + 2))
        ;;
      *) _i=$((_i + 1)) ;;
    esac
  done

  if ! "$_caller_sidecar_set" && ! "$_caller_sha256_set"; then
    local _sc_tmp _sc_file _sc_hash _sc_candidate
    _sc_tmp="$(file__mktmpdir "release-sidecar-probe")"
    for _sc_candidate in \
      "${_asset_uri}.sha256" \
      "${_release_base}/SHA256SUMS" \
      "${_release_base}/sha256sum.txt"; do
      _sc_file="${_sc_tmp}/$(basename "$_sc_candidate")"
      if net__fetch_url_file "$_sc_candidate" "$_sc_file" "${_probe_auth[@]}" 2> /dev/null; then
        _sc_hash="$(_uri__sidecar_hash "$_asset_name" "$_sc_file")"
        if [[ -n "$_sc_hash" ]]; then
          logging__info "auto-detected sidecar at '${_sc_candidate}'"
          _sidecar_arg=(--sidecar "file://${_sc_file}")
          break
        fi
      fi
    done
    if [[ "${#_sidecar_arg[@]}" -eq 0 ]]; then
      logging__info "no sidecar found for '${_asset_name}' — skipping sidecar SHA-256."
    fi
  fi

  # ── Delegate to uri__fetch_asset ────────────────────────────────────────────
  logging__install "Installing release asset '${_asset_name}' from '${_asset_uri}'."
  uri__fetch_asset "$_asset_uri" \
    "${_sidecar_arg[@]}" \
    "${_passthrough[@]}"
}
