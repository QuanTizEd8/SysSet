# shellcheck shell=bash
# File and archive helpers: extract `.tar.xz`, `.tar.gz`, `.tgz`, and `.zip` archives.
#
# Session scratch (`_FILE__SESSION_ROOT`, `file__session_*`, `file__tmpdir`) lives in this
# module. Call `file__session_cleanup` on installer exit (even when logging was never set up).
#
# Returns 1 on unrecognized format or missing extraction tool.

_FILE__SESSION_ROOT=
# True when this process created _FILE__SESSION_ROOT (`file__session_cleanup` may rm -rf).
_FILE__SESSION_OWNED=false

_file__ensure_extract_tool() {
  # _file__ensure_extract_tool <ext> (internal) — Ensure the extraction tool for <ext> is available.
  # Dispatches to the corresponding bootstrap__ function.
  # <ext>: "zip", "xz", "bz2", "gz", "tar".
  local _ext="$1"
  case "$_ext" in
    zip) bootstrap__unzip ;;
    xz) bootstrap__xz ;;
    bz2) bootstrap__bzip2 ;;
    gz) bootstrap__gzip ;;
    tar) bootstrap__tar ;;
    *) return 0 ;;
  esac
}

file__append_privileged() {
  # @brief file__append_privileged <file> — Append stdin to <file>, escalating privilege only if needed.
  #
  # If <file> is writable by the current process (or does not yet exist but its
  # parent directory is writable), appends directly. Otherwise delegates to
  # `users__run_privileged` so the append runs as root. Writability is checked
  # before reading stdin so the stream is never consumed before the path is chosen.
  #
  # Args:
  #   <file>  Absolute path to the file to append to.
  #
  # Returns: 0 on success, non-zero on failure.
  local _file="$1"
  if [ -w "$_file" ] || { [ ! -e "$_file" ] && [ -w "$(dirname "$_file")" ]; }; then
    cat >> "$_file"
  else
    # shellcheck disable=SC2016
    users__run_privileged sh -c 'cat >> "$1"' _ "$_file"
  fi
}

file__install_dir() {
  # @brief file__install_dir [--owner <user>] [--group <group>] [--mode <mode>] <dir>... — Create one or more directories with specified ownership and permissions.
  #
  # Uses `install -d` (GNU coreutils on Linux, BSD utils on macOS — identical
  # flags on both). Sets ownership and mode both on creation and on pre-existing
  # directories. Installs coreutils via ospkg if `install` is not available.
  #
  # Args:
  #   --owner <user>  Owner username. Optional.
  #   --group <group> Group name. Optional.
  #   --mode <mode>   Permissions in octal (default: 0755).
  #   <dir>...        One or more directory paths to create.
  #
  # Returns: 0 on success, 1 if `install` is unavailable or the operation fails.
  local _owner="" _group="" _mode="0755"
  local -a _dirs=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --owner)
        _owner="$2"
        shift 2
        ;;
      --group)
        _group="$2"
        shift 2
        ;;
      --mode)
        _mode="$2"
        shift 2
        ;;
      *)
        _dirs+=("$1")
        shift
        ;;
    esac
  done
  if [[ ${#_dirs[@]} -eq 0 ]]; then
    logging__error "no directories specified"
    return 1
  fi
  bootstrap__install_cmd
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "install command is required to create directories."
    return "$_rc"
  }
  local -a _cmd=(install -d -m "$_mode")
  [[ -n "$_owner" ]] && _cmd+=(-o "$_owner")
  [[ -n "$_group" ]] && _cmd+=(-g "$_group")
  # Escalate when setting ownership to another user, or when any target dir
  # (or its nearest existing ancestor) is not writable by the current process.
  local _needs_priv=false
  if [[ -n "$_owner" && "$_owner" != "$(users__get_current --no-sudo)" ]]; then
    _needs_priv=true
  else
    local _d _existing
    for _d in "${_dirs[@]}"; do
      _existing="$(file__nearest_existing "$_d")"
      [[ ! -w "$_existing" ]] && {
        _needs_priv=true
        break
      }
    done
  fi
  logging__debug "Creating install directories: ${_dirs[*]} (mode=${_mode})."
  local _rc=0
  if $_needs_priv; then
    users__run_privileged "${_cmd[@]}" "${_dirs[@]}" || _rc=$?
  else
    "${_cmd[@]}" "${_dirs[@]}" || _rc=$?
  fi
  if ((_rc != 0)); then
    logging__error "failed to create directories: ${_dirs[*]}."
    return 1
  fi
  return 0
}

file__mkdir() {
  # @brief file__mkdir <dir>... — Create directories (mkdir -p), escalating privilege only if needed.
  #
  # Uses `mkdir -p` for each path. Escalates to `users__run_privileged` if the
  # nearest existing ancestor of any target directory is not writable by the
  # current process.
  #
  # Args:
  #   <dir>...  One or more directory paths to create.
  #
  # Returns: 0 on success, non-zero on failure.
  logging__debug "Creating directories: $*."
  local _needs_priv=false _d
  for _d in "$@"; do
    [[ ! -w "$(file__nearest_existing "$_d")" ]] && {
      _needs_priv=true
      break
    }
  done
  if $_needs_priv; then
    users__run_privileged mkdir -p "$@"
  else
    mkdir -p "$@"
  fi
}

file__cp() {
  # @brief file__cp <arg>... — Copy files or directories (cp), escalating privilege only if needed.
  #
  # Forwards all arguments to `cp`. The destination is the last argument.
  # Escalates to `users__run_privileged` if the destination (or its nearest
  # existing ancestor) is not writable by the current process.
  #
  # Args:
  #   <arg>...  Any combination of `cp` flags, source paths, and destination (last arg).
  #
  # Returns: 0 on success, non-zero on failure.
  logging__debug "Copying files (dest='${!#}')."
  local _dest="${!#}"
  local _needs_priv=false
  if [[ -e "$_dest" && ! -w "$_dest" ]]; then
    _needs_priv=true
  elif [[ ! -e "$_dest" && ! -w "$(file__nearest_existing "$(dirname "$_dest")")" ]]; then
    _needs_priv=true
  fi
  if $_needs_priv; then
    users__run_privileged cp "$@"
  else
    cp "$@"
  fi
}

file__mv() {
  # @brief file__mv [flags] <src>... <dest> — Move files or directories (mv), escalating privilege only if needed.
  #
  # Forwards all arguments to `mv`. The destination is the last argument.
  # Escalates to `users__run_privileged` if the destination (or its nearest
  # existing ancestor) is not writable by the current process.
  #
  # Args:
  #   [flags]   Optional mv flags. Must appear before paths.
  #   <src>...  Source path(s).
  #   <dest>    Destination path (last argument).
  #
  # Returns: 0 on success, non-zero on failure.
  logging__debug "Moving files (dest='${!#}')."
  local _dest="${!#}"
  local _needs_priv=false
  if [[ -e "$_dest" && ! -w "$_dest" ]]; then
    _needs_priv=true
  elif [[ ! -e "$_dest" && ! -w "$(file__nearest_existing "$(dirname "$_dest")")" ]]; then
    _needs_priv=true
  fi
  if $_needs_priv; then
    users__run_privileged mv "$@"
  else
    mv "$@"
  fi
}

file__rm() {
  # @brief file__rm [flags] <path>... — Remove files or directories (rm), escalating privilege only if needed.
  #
  # Forwards all arguments to `rm`. Escalates to `users__run_privileged` if the
  # parent directory of any existing target path is not writable by the current
  # process.
  #
  # Args:
  #   [flags]   Optional rm flags (e.g. -rf, -r, -f). Must appear before paths.
  #   <path>... One or more target paths to remove.
  #
  # Returns: 0 on success, non-zero on failure.
  local -a _flags=() _paths=()
  local _done_flags=false
  while [[ $# -gt 0 ]]; do
    if ! $_done_flags && [[ "$1" == -* ]]; then
      _flags+=("$1")
      shift
    else
      _done_flags=true
      _paths+=("$1")
      shift
    fi
  done
  ((${#_paths[@]} > 0)) && logging__remove "Removing paths: ${_paths[*]}."
  local _needs_priv=false _p
  for _p in "${_paths[@]}"; do
    if [[ -e "$_p" || -L "$_p" ]]; then
      [[ ! -w "$(dirname "$_p")" ]] && {
        _needs_priv=true
        break
      }
    fi
  done
  if $_needs_priv; then
    users__run_privileged rm "${_flags[@]+"${_flags[@]}"}" "${_paths[@]}"
  else
    rm "${_flags[@]+"${_flags[@]}"}" "${_paths[@]}"
  fi
}

file__ln() {
  # @brief file__ln [flags] <target> <link_name> — Create a symlink (ln), escalating privilege only if needed.
  #
  # Forwards all arguments to `ln`. Escalates to `users__run_privileged` if the
  # directory containing <link_name> is not writable by the current process.
  #
  # Args:
  #   [flags]      Optional ln flags (e.g. -s, -f, -n, -sfn).
  #   <target>     The target the symlink points to.
  #   <link_name>  Path where the symlink is created (last argument).
  #
  # Returns: 0 on success, non-zero on failure.
  local _link_name="${!#}"
  local _needs_priv=false
  local _parent
  _parent="$(dirname "$_link_name")"
  if [[ -e "$_link_name" || -L "$_link_name" ]]; then
    [[ ! -w "$_parent" ]] && _needs_priv=true
  elif [[ ! -w "$(file__nearest_existing "$_parent")" ]]; then
    _needs_priv=true
  fi
  logging__debug "Creating symlink '${_link_name}'."
  local _rc=0
  if $_needs_priv; then
    users__run_privileged ln "$@" || _rc=$?
  else
    ln "$@" || _rc=$?
  fi
  if ((_rc != 0)); then
    logging__error "failed to create symlink '${_link_name}'."
    return 1
  fi
  return 0
}

file__chmod() {
  # @brief file__chmod [flags] <mode> <path>... — chmod, escalating privilege only if needed.
  #
  # Parses leading flags (e.g. `-R`), then the mode, then one or more paths.
  # Escalates to `users__run_privileged` if any path (or its nearest existing
  # ancestor) is not writable by the current process.
  #
  # Args:
  #   [flags]   Optional chmod flags (e.g. -R). Must appear before <mode>.
  #   <mode>    Permission mode (e.g. 644, +x, g+rw).
  #   <path>... One or more target paths.
  #
  # Returns: 0 on success, non-zero on failure.
  local -a _flags=() _paths=()
  local _mode=""
  while [[ $# -gt 0 ]]; do
    if [[ -z "$_mode" && "$1" == -* ]]; then
      _flags+=("$1")
      shift
    elif [[ -z "$_mode" ]]; then
      _mode="$1"
      shift
    else
      _paths+=("$1")
      shift
    fi
  done
  local _needs_priv=false _p
  for _p in "${_paths[@]}"; do
    if [[ -e "$_p" && ! -w "$_p" ]]; then
      _needs_priv=true
      break
    elif [[ ! -e "$_p" && ! -w "$(file__nearest_existing "$_p")" ]]; then
      _needs_priv=true
      break
    fi
  done
  local _rc=0
  if $_needs_priv; then
    users__run_privileged chmod "${_flags[@]+"${_flags[@]}"}" "$_mode" "${_paths[@]}" || _rc=$?
  else
    chmod "${_flags[@]+"${_flags[@]}"}" "$_mode" "${_paths[@]}" || _rc=$?
  fi
  if ((_rc != 0)); then
    logging__error "failed to chmod '${_mode}' on: ${_paths[*]}."
    return 1
  fi
  return 0
}

file__chown() {
  # @brief file__chown [flags] <spec> <path>... — chown, escalating privilege only if needed.
  #
  # Parses leading flags (e.g. `-R`), then the owner spec, then one or more
  # paths. Escalates to `users__run_privileged` if the spec references a
  # different user than the current one, or if any path (or its nearest existing
  # ancestor) is not writable by the current process.
  #
  # Args:
  #   [flags]   Optional chown flags (e.g. -R). Must appear before <spec>.
  #   <spec>    Owner spec (e.g. user, user:group).
  #   <path>... One or more target paths.
  #
  # Returns: 0 on success, non-zero on failure.
  local -a _flags=() _paths=()
  local _spec=""
  while [[ $# -gt 0 ]]; do
    if [[ -z "$_spec" && "$1" == -* ]]; then
      _flags+=("$1")
      shift
    elif [[ -z "$_spec" ]]; then
      _spec="$1"
      shift
    else
      _paths+=("$1")
      shift
    fi
  done
  # Privilege is needed when the spec names a different user, or when any
  # target path is not writable by the current process.
  local _spec_user="${_spec%%:*}"
  local _needs_priv=false _p
  if [[ -n "$_spec_user" && "$_spec_user" != "$(users__get_current --no-sudo)" ]]; then
    _needs_priv=true
  else
    for _p in "${_paths[@]}"; do
      if [[ -e "$_p" && ! -w "$_p" ]]; then
        _needs_priv=true
        break
      elif [[ ! -e "$_p" && ! -w "$(file__nearest_existing "$_p")" ]]; then
        _needs_priv=true
        break
      fi
    done
  fi
  local _rc=0
  if $_needs_priv; then
    users__run_privileged chown "${_flags[@]+"${_flags[@]}"}" "$_spec" "${_paths[@]}" || _rc=$?
  else
    chown "${_flags[@]+"${_flags[@]}"}" "$_spec" "${_paths[@]}" || _rc=$?
  fi
  if ((_rc != 0)); then
    logging__error "failed to chown '${_spec}' on: ${_paths[*]}."
    return 1
  fi
  return 0
}

file__tee() {
  # @brief file__tee [--append] <file> — Write stdin to <file>, escalating privilege only if needed.
  #
  # If <file> is writable by the current process (or does not yet exist but its
  # parent directory is writable), writes directly via `cat`. Otherwise delegates
  # to `users__run_privileged`. stdout is always suppressed.
  #
  # Args:
  #   --append  Append to <file> rather than overwrite. Alias: -a.
  #   <file>    Destination path.
  #
  # Returns: 0 on success, non-zero on failure.
  local _append=false _file=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --append | -a)
        _append=true
        shift
        ;;
      *)
        _file="$1"
        shift
        ;;
    esac
  done
  if [[ -z "$_file" ]]; then
    logging__error "no file specified"
    return 1
  fi
  local _needs_priv=false
  if [[ -f "$_file" && ! -w "$_file" ]]; then
    _needs_priv=true
  elif [[ ! -f "$_file" && ! -w "$(file__nearest_existing "$(dirname "$_file")")" ]]; then
    _needs_priv=true
  fi
  local _rc=0
  if $_needs_priv; then
    if $_append; then
      # shellcheck disable=SC2016
      users__run_privileged sh -c 'cat >> "$1"' _ "$_file" || _rc=$?
    else
      # shellcheck disable=SC2016
      users__run_privileged sh -c 'cat > "$1"' _ "$_file" || _rc=$?
    fi
  else
    if $_append; then
      cat >> "$_file" || _rc=$?
    else
      cat > "$_file" || _rc=$?
    fi
  fi
  if ((_rc != 0)); then
    logging__error "failed to write '${_file}'."
    return 1
  fi
  return 0
}

file__resolve_backup_policy() {
  # @brief file__resolve_backup_policy <policy> — Resolve a backup policy ("auto"/"true"/"false") to a concrete "true"/"false".
  #
  # "auto" resolves via os__is_devcontainer_runtime: back up outside a
  # devcontainer/Codespaces runtime, skip inside one (where the container
  # itself is disposable and a backup adds little value).
  #
  # Args:
  #   <policy>  One of "auto", "true", "false".
  #
  # Stdout: "true" or "false".
  local _policy="${1:-auto}"
  case "$_policy" in
    true) printf 'true\n' ;;
    false) printf 'false\n' ;;
    *)
      if os__is_devcontainer_runtime; then
        printf 'false\n'
      else
        printf 'true\n'
      fi
      ;;
  esac
}

file__backup_if_policy() {
  # @brief file__backup_if_policy <path> <policy> <backup_dir> — Back up <path> into <backup_dir> when <policy> (resolved via file__resolve_backup_policy) is "true".
  #
  # No-ops (prints nothing, returns 0) when <path> does not exist or the
  # resolved policy is "false". The backup name is a slugified copy of <path>
  # (slashes replaced with underscores) suffixed with a UTC timestamp, so
  # repeated backups of the same path never collide.
  #
  # Args:
  #   <path>        File or directory to back up (need not exist).
  #   <policy>      "auto", "true", or "false" (see file__resolve_backup_policy).
  #   <backup_dir>  Directory to copy the backup into. Required when a backup is taken.
  #
  # Stdout: the backup path, only when a backup was actually taken.
  #
  # Returns: 0 on success (including no-op cases), 1 if a backup is needed but <backup_dir> is empty.
  local _path="${1-}" _policy="${2-}" _backup_dir="${3-}"
  [[ -e "$_path" ]] || return 0
  [[ "$(file__resolve_backup_policy "$_policy")" == "true" ]] || return 0
  if [[ -z "$_backup_dir" ]]; then
    logging__error "file__backup_if_policy: no backup directory provided for '${_path}'."
    return 1
  fi
  local _slug _ts _dest
  _slug="$(printf '%s' "$_path" | tr '/' '_')"
  _slug="${_slug#_}"
  _ts="$(date -u +%Y%m%dT%H%M%SZ)"
  _dest="${_backup_dir}/${_slug}.${_ts}"
  file__mkdir "$_backup_dir"
  file__cp -r "$_path" "$_dest"
  printf '%s\n' "$_dest"
}

file__detect_type() {
  # @brief file__detect_type <file> — Detect file type from magic bytes.
  #
  # Reads the first 6 bytes of <file> to identify its format, independent of
  # filename or extension.
  #
  # Stdout: one of: gzip | xz | bzip2 | zip | elf | macho | script | unknown
  # Returns: 0 always (unknown is a valid result, not an error).
  local _file="$1" _hex
  _hex="$(od -An -tx1 -N 6 "$_file" 2> /dev/null | tr -d ' \n')"
  case "${_hex}" in
    1f8b*) printf 'gzip' ;;
    fd377a585a00*) printf 'xz' ;;
    425a68*) printf 'bzip2' ;;
    504b0304*) printf 'zip' ;;
    7f454c46*) printf 'elf' ;;
    cafebabe* | cefaedfe* | cffaedfe*) printf 'macho' ;;
    2321*) printf 'script' ;;
    *) printf 'unknown' ;;
  esac
}

file__extract_archive() {
  # @brief file__extract_archive <archive_file> <dest_dir> [<original_name>] [--strip N] — Extract a `.tar.xz`, `.tar.gz`, `.tgz`, `.tar.bz2`, or `.zip` archive to `<dest_dir>`.
  #
  # `<original_name>` is used for format detection when `<archive_file>` is a temp
  # path with no meaningful extension (e.g. a mktemp output). When omitted,
  # the basename of `<archive_file>` is used.
  #
  # Args:
  #   <archive_file>   Path to the archive to extract.
  #   <dest_dir>       Destination directory (created if absent).
  #   <original_name>  Optional filename used for extension-based format detection.
  #   --strip N        Strip N leading path components (tar --strip-components=N). Ignored for zip.
  #
  # Returns: 0 on success, 1 on unrecognized format or missing extraction tool.
  local _arc="$1" _dest="$2"
  local _name _strip=""
  if [ "${3:-}" = "--strip" ]; then
    _name="$(basename "$_arc")"
    _strip="${4:-}"
  elif [ "${4:-}" = "--strip" ]; then
    _name="${3:-$(basename "$_arc")}"
    _strip="${5:-}"
  else
    _name="${3:-$(basename "$_arc")}"
  fi
  local -a _strip_arg=()
  [ -n "$_strip" ] && _strip_arg=(--strip-components="$_strip")
  logging__install "Extracting archive '${_arc}' to '${_dest}'."
  mkdir -p "$_dest"
  case "$_name" in
    *.tar.xz)
      _file__ensure_extract_tool tar
      local _rc=$?
      [[ $_rc == 0 ]] || {
        logging__error "tar is required to extract '${_name}'."
        return "$_rc"
      }
      _file__ensure_extract_tool xz
      local _rc=$?
      [[ $_rc == 0 ]] || {
        logging__error "xz is required to extract '${_name}'."
        return "$_rc"
      }
      tar --no-same-owner -xJf "$_arc" -C "$_dest" "${_strip_arg[@]}"
      ;;
    *.tar.gz | *.tgz)
      _file__ensure_extract_tool tar
      local _rc=$?
      [[ $_rc == 0 ]] || {
        logging__error "tar is required to extract '${_name}'."
        return "$_rc"
      }
      _file__ensure_extract_tool gz
      local _rc=$?
      [[ $_rc == 0 ]] || {
        logging__error "gzip is required to extract '${_name}'."
        return "$_rc"
      }
      tar --no-same-owner -xzf "$_arc" -C "$_dest" "${_strip_arg[@]}"
      ;;
    *.tar.bz2)
      _file__ensure_extract_tool tar
      local _rc=$?
      [[ $_rc == 0 ]] || {
        logging__error "tar is required to extract '${_name}'."
        return "$_rc"
      }
      _file__ensure_extract_tool bz2
      local _rc=$?
      [[ $_rc == 0 ]] || {
        logging__error "bzip2 is required to extract '${_name}'."
        return "$_rc"
      }
      tar --no-same-owner -xjf "$_arc" -C "$_dest" "${_strip_arg[@]}"
      ;;
    *.zip)
      _file__ensure_extract_tool zip
      local _rc=$?
      [[ $_rc == 0 ]] || {
        logging__error "unzip is required to extract '${_name}'."
        return "$_rc"
      }
      unzip -q -o "$_arc" -d "$_dest"
      ;;
    *)
      logging__warn "Unrecognized archive format: '$(basename "$_name")'; skipping extraction."
      return 1
      ;;
  esac
  logging__success "Extracted archive '${_arc}' to '${_dest}'."
}

file__nearest_existing() {
  # @brief file__nearest_existing <path> — Walk up dirname until an existing path component is found.
  #
  # Useful for resolving ownership or write permission of a path that may not yet
  # exist by examining the nearest ancestor that does.
  #
  # Args:
  #   <path>  Absolute path to examine (need not exist). Must be absolute; relative
  #           paths cause dirname to loop on "." indefinitely.
  #
  # Stdout: nearest existing ancestor path (or `/` when nothing above root exists).
  local _p="$1"
  [[ "$_p" = /* ]] || {
    logging__error "path must be absolute: '${_p}'"
    return 1
  }
  while [[ "$_p" != "/" && ! -e "$_p" ]]; do _p="$(dirname "$_p")"; done
  printf '%s\n' "$_p"
}

file__session_ensure() {
  # @brief file__session_ensure — Lazy-init the installer session scratch root.
  #
  # Exports `_FILE__SESSION_ROOT` so command-substitution subshells and child shells
  # share the same path. Does not take ownership when the root was pre-set (e.g. unit
  # tests pinning `_FILE__SESSION_ROOT` to `BATS_TEST_TMPDIR`).
  if [[ -n "${_FILE__SESSION_ROOT:-}" ]]; then
    export _FILE__SESSION_ROOT
    return 0
  fi
  _FILE__SESSION_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/devfeats_XXXXXX")"
  _FILE__SESSION_OWNED=true
  export _FILE__SESSION_ROOT
  return 0
}

file__session_root() {
  # @brief file__session_root — Print the session scratch root (initialises if needed).
  file__session_ensure
  printf '%s\n' "${_FILE__SESSION_ROOT}"
  return 0
}

file__session_cleanup() {
  # @brief file__session_cleanup — Remove owned session scratch and reset globals.
  #
  # No-op when the root was injected (not created by `file__session_ensure`).
  if [[ "${_FILE__SESSION_OWNED:-}" == true && -n "${_FILE__SESSION_ROOT:-}" ]]; then
    logging__clean "Removing session scratch tree '${_FILE__SESSION_ROOT}'."
    rm -rf "${_FILE__SESSION_ROOT}"
  else
    logging__skip "Session scratch tree not owned by this process; skipping cleanup."
  fi
  _FILE__SESSION_ROOT=
  _FILE__SESSION_OWNED=false
  unset _FILE__SESSION_ROOT
  return 0
}

file__tmpdir() {
  # @brief file__tmpdir [<name>] — Return (and create if needed) a named subdirectory of `_FILE__SESSION_ROOT`. Idempotent.
  #
  # Safe before `logging__setup`. The tree is removed by `file__session_cleanup` on exit.
  #
  # Args:
  #   [<name>]  Subdirectory under `_FILE__SESSION_ROOT` (may contain `/`). When omitted,
  #             returns the session root itself.
  #
  # Stdout: absolute path to the named subdirectory (or the session root when called with no args).
  # shellcheck disable=SC2120  # callers in other sourced files are invisible to shellcheck
  file__session_ensure
  if [[ -n "${1:-}" ]]; then
    mkdir -p "${_FILE__SESSION_ROOT}/${1}"
    printf '%s\n' "${_FILE__SESSION_ROOT}/${1}"
  else
    printf '%s\n' "${_FILE__SESSION_ROOT}"
  fi
  return 0
}

file__mktmpdir() {
  # @brief file__mktmpdir <label> — Create and return a new unique directory under `_FILE__SESSION_ROOT`.
  #
  # Unlike `file__tmpdir`, each call creates a distinct directory via `mktemp`.
  # Use when per-call isolation is required (e.g. GPG homedirs, OCI pull dirs
  # that may be called multiple times with different artifacts). Removed by
  # `file__session_cleanup` at script exit.
  #
  # Args:
  #   <label>  Short label used as a prefix in the directory name.
  #
  # Stdout: absolute path to the new unique directory.
  local _base _label="${1:-tmp}"
  file__session_ensure
  _base="${_FILE__SESSION_ROOT}/${_label}"
  mkdir -p "${_base%/*}"
  mktemp -d "${_base}.XXXXXX"
}

file__first_child_dir() {
  # @brief file__first_child_dir <dir> — Print the first immediate subdirectory of <dir>, or nothing.
  #
  # Non-recursive; order is undefined (same as `find … -maxdepth 1 -mindepth 1 -type d | head -1`).
  # Enables `dotglob` briefly so hidden directory names (e.g. `.src/`) are included, matching find.
  #
  # Args:
  #   <dir>  Parent directory to scan.
  #
  # Stdout: absolute or relative path to the first child directory found.
  # Returns: 0 always.
  local _dir="$1" _child="" _candidate _dotglob_was_on=false
  [[ -n "$_dir" && -d "$_dir" ]] || return 0
  shopt -q dotglob && _dotglob_was_on=true
  shopt -s dotglob
  for _candidate in "$_dir"/*; do
    [[ -d "$_candidate" ]] || continue
    _child="$_candidate"
    break
  done
  [[ "$_dotglob_was_on" == false ]] && shopt -u dotglob
  [[ -n "$_child" ]] && printf '%s\n' "$_child"
  return 0
}

file__first_glob_match() {
  # @brief file__first_glob_match <dir> <glob> — Print the first regular file in <dir> matching <glob>.
  #
  # Non-recursive; <glob> is a filename pattern (e.g. `*.deb`, `*.zsh-theme`).
  #
  # Args:
  #   <dir>   Directory to scan.
  #   <glob>  Bash glob pattern applied to basenames in <dir>.
  #
  # Stdout: path to the first matching regular file.
  # Returns: 0 always.
  local _dir="$1" _glob="$2" _match="" _candidate
  [[ -n "$_dir" && -d "$_dir" && -n "$_glob" ]] || return 0
  for _candidate in "$_dir"/$_glob; do
    [[ -f "$_candidate" ]] || continue
    _match="$_candidate"
    break
  done
  [[ -n "$_match" ]] && printf '%s\n' "$_match"
  return 0
}

file__canonical_path() {
  # @brief file__canonical_path <path> — Resolve symlinks and return the canonical absolute path.
  #
  # Tries each resolver in order, stopping at the first that succeeds:
  #   1. `realpath`   (GNU coreutils; not available on stock macOS)
  #   2. `readlink -f` (GNU readlink; not available on stock macOS BSD readlink)
  #   3. `readlink`   (BSD/GNU; returns the immediate symlink target without canonicalising
  #                   ancestor directories — sufficient when the target is absolute)
  #   4. The original path unchanged (final fallback).
  #
  # On macOS, steps 1–2 fail unless coreutils is installed, so step 3 handles the
  # common case.  If `readlink` returns a relative path, the caller should prepend
  # `$(dirname <path>)` to make it absolute.
  #
  # Args:
  #   <path>  Path to canonicalise (need not exist when using steps 3–4).
  #
  # Stdout: canonical path string.
  local _p="$1"
  realpath "$_p" 2> /dev/null ||
    readlink -f "$_p" 2> /dev/null ||
    readlink "$_p" 2> /dev/null ||
    printf '%s' "$_p"
}
