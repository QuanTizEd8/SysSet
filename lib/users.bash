# shellcheck shell=bash
# User management: resolve users, set login shells, manage installation prefixes.
#
# Provides helpers for detecting root, resolving the remote user list from
# devcontainer env vars, managing file permissions, and setting the login shell
# for one or more users. Works on Alpine (patching PAM), Debian-based, and macOS.

users__is_root() {
  # @brief users__is_root — Return 0 when the current process runs as root (uid 0), 1 otherwise.
  #
  # Checks via `id -u` when available; falls back to bash's $EUID when id is
  # not yet installed (e.g. during the coreutils bootstrap). Returns 1 when
  # neither source is available.
  #
  # Returns: 0 if uid is 0, 1 otherwise.
  if command -v id > /dev/null 2>&1; then
    [ "$(id -u)" -eq 0 ]
  elif [[ -n "${EUID+x}" ]]; then
    [[ ${EUID} -eq 0 ]]
  else
    return 1
  fi
}

users__is_privileged() {
  # @brief users__is_privileged — Return 0 when the current process can run privileged commands.
  #
  # A process is considered privileged when it is root (uid 0), or when `sudo`
  # is installed and configured for passwordless operation.
  #
  # No output is produced; intended as a boolean predicate.
  #
  # Returns: 0 if privileged, 1 otherwise.
  users__is_root && return 0
  command -v sudo > /dev/null 2>&1 && sudo -n true 2> /dev/null
}

users__can_write() {
  # @brief users__can_write <path> — Return 0 if the calling process can write to <path> (or create it if nonexistent).
  #
  # A path is considered writable when:
  #   1. The path itself (or its nearest existing ancestor) is writable by the current process, OR
  #   2. Passwordless sudo is available (users__is_privileged returns 0).
  #
  # Args:
  #   <path>  Absolute path to check (need not exist).
  #
  # Returns: 0 if writable or privileged, 1 otherwise.
  local _path="$1" _existing
  _existing="$(file__nearest_existing "$_path")"
  [ -w "$_existing" ] && return 0
  users__is_privileged
}

users__run_as() {
  # @brief users__run_as <user> [--cwd <dir>] -- <command> [args] — Run a command as `<user>`: in-process if already that user, otherwise via `su -l` with bash-quoted argv.
  #
  # Requires `bash` on PATH for the non-self path. Bootstraps `su` via ospkg when absent.
  #
  # Args:
  #   <user>       Username to run as.
  #   --cwd <dir>  Working directory for the command (optional).
  #   -- <cmd>...  Command and arguments to execute.
  local _or_u _or_cd _or_c _or_cd_q
  if [ -z "$1" ]; then
    logging__error "username is required."
    return 1
  fi
  _or_u=$1
  shift
  _or_cd=""
  case $1 in
    --cwd)
      _or_cd=$2
      if [ -z "$_or_cd" ]; then
        logging__error "--cwd requires a directory path."
        return 1
      fi
      shift 2
      ;;
  esac
  case $1 in
    --) shift ;;
  esac
  if [ $# -eq 0 ]; then
    logging__error "command is required after --."
    return 1
  fi

  if [ "$(users__get_current --no-sudo)" = "$_or_u" ]; then
    if [ -n "$_or_cd" ]; then
      (cd "$_or_cd" && "$@")
    else
      "$@"
    fi
    return $?
  fi
  if ! shell__bash --version > /dev/null 2>&1; then
    logging__error "bash is required to run a command as another user"
    return 1
  fi
  # shellcheck disable=SC2016  # $a and $1 are intentionally single-quoted — evaluated by the subprocess bash
  _or_c="$(shell__bash -c 'for a; do printf " %q" "$a"; done; echo' sh "$@")"
  _or_c="${_or_c# }" # strip the single leading space; $(...) already strips the trailing newline
  if ! command -v su > /dev/null 2>&1; then
    bootstrap__su || {
      logging__error "su is required to run as user '${_or_u}'."
      return 1
    }
  fi
  if [ -n "$_or_cd" ]; then
    # shellcheck disable=SC2016  # $1 is intentionally single-quoted — evaluated by the subprocess bash
    _or_cd_q="$(shell__bash -c 'printf "%q" "$1"' bash "$_or_cd")"
    users__run_privileged su -l "$_or_u" -c "cd ${_or_cd_q} && ${_or_c}"
  else
    users__run_privileged su -l "$_or_u" -c "$_or_c"
  fi
  return $?
}

users__run_privileged() {
  # @brief users__run_privileged <cmd> [<args>...] — Run a command as root.
  #
  # If already root (uid 0), runs directly. Otherwise requires sudo to be
  # pre-installed and configured for passwordless operation.
  #
  # Args:
  #   <cmd> [<args>...]  Command and arguments to execute.
  #
  # Returns: the exit code of <cmd>.
  if users__is_root; then
    "$@"
  else
    if ! command -v sudo > /dev/null 2>&1; then
      logging__error "sudo is not installed (cmd='${*}')"
      return 1
    fi
    if ! sudo -n true 2> /dev/null; then
      logging__error "passwordless sudo required but not available (uid=${EUID}, user=$(id -un 2> /dev/null || printf '%s' "${USER:-?}"), cmd='${*}')"
      return 1
    fi
    sudo -n "$@"
  fi
}

users__default_prefix() {
  # @brief users__default_prefix — Print the default binary installation prefix.
  #
  # Returns `/usr/local` when the calling process can write there (directly or
  # via passwordless sudo). Otherwise resolves the current user's home via
  # `users__resolve_home` and returns `<home>/.local`.
  #
  # Stdout: absolute prefix path.
  if users__can_write "/usr/local"; then
    printf '%s\n' "/usr/local"
    return 0
  fi
  local _home
  _home="$(users__resolve_home)"
  if [[ -z "$_home" ]]; then
    logging__error "cannot resolve home directory for current user."
    return 1
  fi
  printf '%s\n' "${_home}/.local"
}

users__primary_group_of() {
  # @brief users__primary_group_of <username> — Print the primary group name of the given user.
  #
  # Args:
  #   <username>  Username to query.
  #
  # Stdout: group name string.
  bootstrap__coreutils
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "coreutils (id) is required to resolve primary group."
    return "$_rc"
  }
  id -gn "$1"
}

users__gid_of_group() {
  # @brief users__gid_of_group <groupname> — Print the numeric GID for the given group name.
  #
  # Args:
  #   <groupname>  Group name to query.
  #
  # Stdout: GID as a decimal string.
  # Returns: 0 on success, 1 when the group is not found.
  local _gid
  if bootstrap__getent && command -v getent > /dev/null 2>&1; then
    _gid="$(getent group "$1" 2> /dev/null | cut -d: -f3)"
    [[ -n "$_gid" ]] && {
      printf '%s\n' "$_gid"
      return 0
    }
  fi
  _gid="$(awk -F: -v g="$1" '$1==g{print $3;exit}' /etc/group 2> /dev/null)"
  [[ -n "$_gid" ]] && {
    printf '%s\n' "$_gid"
    return 0
  }
  logging__error "group '${1}' not found."
  return 1
}

users__group_of_gid() {
  # @brief users__group_of_gid <gid> — Print the group name for the given numeric GID.
  #
  # Args:
  #   <gid>  Numeric GID to query.
  #
  # Stdout: group name string.
  # Returns: 0 on success, 1 when no group with that GID is found.
  local _gname
  if bootstrap__getent && command -v getent > /dev/null 2>&1; then
    _gname="$(getent group "$1" 2> /dev/null | cut -d: -f1)"
    [[ -n "$_gname" ]] && {
      printf '%s\n' "$_gname"
      return 0
    }
  fi
  _gname="$(awk -F: -v gid="$1" '$3==gid{print $1;exit}' /etc/group 2> /dev/null)"
  [[ -n "$_gname" ]] && {
    printf '%s\n' "$_gname"
    return 0
  }
  logging__error "no group found for GID '${1}'."
  return 1
}

users__uid_of_user() {
  # @brief users__uid_of_user <username> — Print the numeric UID of the given user.
  #
  # Args:
  #   <username>  Username to query.
  #
  # Stdout: UID as a decimal string.
  bootstrap__coreutils
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "coreutils (id) is required to resolve user UID."
    return "$_rc"
  }
  id -u "$1"
}

users__username_of_uid() {
  # @brief users__username_of_uid <uid> — Print the username for the given numeric UID.
  #
  # Args:
  #   <uid>  Numeric UID to query.
  #
  # Stdout: username string.
  bootstrap__coreutils
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "coreutils (id) is required to resolve username from UID."
    return "$_rc"
  }
  local _uname
  _uname="$(id -un "$1" 2> /dev/null)" && {
    printf '%s\n' "$_uname"
    return 0
  }
  # busybox id(1) does not accept numeric UID arguments; fall back to passwd db.
  _uname="$(getent passwd "$1" 2> /dev/null | cut -d: -f1)"
  [[ -z "$_uname" ]] && _uname="$(awk -F: -v u="$1" '$3==u{print $1;exit}' /etc/passwd 2> /dev/null)"
  [[ -n "$_uname" ]] && {
    printf '%s\n' "$_uname"
    return 0
  }
  logging__error "no username found for UID '${1}'."
  return 1
}

users__users_by_primary_gid() {
  # @brief users__users_by_primary_gid <gid> — Print all usernames whose primary GID matches <gid>, one per line.
  #
  # Args:
  #   <gid>  Numeric GID to query.
  #
  # Stdout: one username per line; empty when no matches are found.
  local _gid="$1"
  if bootstrap__getent && command -v getent > /dev/null 2>&1; then
    getent passwd | awk -F: -v gid="$_gid" '$4==gid{print $1}'
    return
  fi
  if [[ "$(os__kernel)" == "Darwin" ]]; then
    dscl . -list /Users PrimaryGroupID 2> /dev/null | awk -v gid="$_gid" '$2==gid{print $1}'
    return
  fi
  awk -F: -v gid="$_gid" '$4==gid{print $1}' /etc/passwd
}

users__group_exists() {
  # @brief users__group_exists <name-or-gid> — Return 0 if a group with the given name or numeric GID exists.
  #
  # Args:
  #   <name-or-gid>  Group name or numeric GID to check.
  #
  # Returns: 0 if found, 1 otherwise.
  if bootstrap__getent && command -v getent > /dev/null 2>&1; then
    getent group "$1" > /dev/null 2>&1
    return
  fi
  awk -F: -v g="$1" '$1==g || $3==g {found=1; exit} END{exit (found ? 0 : 1)}' /etc/group 2> /dev/null
}

users__uid_of_path_owner() {
  # @brief users__uid_of_path_owner <path> — Print the numeric owner UID of the given path.
  #
  # Branches on os__kernel: stat -f '%u' on Darwin, stat -c '%u' on Linux.
  #
  # Args:
  #   <path>  Absolute path to query (must exist).
  #
  # Stdout: owner UID as a decimal string.
  bootstrap__coreutils
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "coreutils (stat) is required to resolve path owner."
    return "$_rc"
  }
  if [[ "$(os__kernel)" == "Darwin" ]]; then
    stat -f '%u' "$1"
  else
    stat -c '%u' "$1"
  fi
}

users__home_of_path_owner() {
  # @brief users__home_of_path_owner <path> — Print the home directory of the user who owns the nearest existing ancestor of <path>.
  #
  # Args:
  #   <path>  Absolute path (need not exist).
  #
  # Stdout: absolute home directory path; empty when the owner has no resolvable home.
  local _p="$1"
  local _existing _uid
  _existing="$(file__nearest_existing "$_p")"
  _uid="$(users__uid_of_path_owner "$_existing")"
  users__resolve_home --uid "$_uid"
}

users__resolve_list() {
  # @brief users__resolve_list — Print one deduplicated username per line.
  #
  # Root is excluded from auto-detected paths (_REMOTE_USER, _CONTAINER_USER,
  # SUDO_USER) when other non-root users are found; it is only added as a
  # fallback when no other user is resolved (e.g. plain container image or
  # standalone macOS install). Root is always accepted via --user.
  #
  # Args:
  #   [--current <bool>]    Include SUDO_USER / current user (default: true).
  #   [--remote <bool>]     Include _REMOTE_USER (default: true).
  #   [--container <bool>]  Include _CONTAINER_USER (default: true).
  #   [--user <name>]...    Extra explicit usernames; root allowed; repeatable.
  #   [--all]               Also include every regular (non-system), interactive-shell
  #                         user found in the password database (UID >=1000 on Linux,
  #                         >=500 on macOS; users with a nologin/false shell are excluded).
  #
  # Stdout: one username per line.
  local _include_current="true"
  local _include_remote="true"
  local _include_container="true"
  local _include_all="false"
  local -a _extra_users=()

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --current)
        _include_current="$2"
        shift 2
        ;;
      --remote)
        _include_remote="$2"
        shift 2
        ;;
      --container)
        _include_container="$2"
        shift 2
        ;;
      --all)
        _include_all="true"
        shift
        ;;
      --user)
        _extra_users+=("$2")
        shift 2
        ;;
      *) shift ;;
    esac
  done

  local _seen="" _out="" _root_queued=false

  __users__add() {
    local _name="$1"
    [ -z "$_name" ] && return 0
    case " ${_seen} " in
      *" ${_name} "*) return 0 ;;
    esac
    _seen="${_seen} ${_name}"
    _out="${_out} ${_name}"
    return 0
  }

  if [ "${_include_current}" = "true" ]; then
    local _cur
    _cur="$(users__get_current)" || true
    if [ "$_cur" != "root" ]; then
      __users__add "$_cur"
    else
      _root_queued=true
    fi
  fi

  if [ "${_include_remote}" = "true" ] && [ -n "${_REMOTE_USER:-}" ]; then
    [ "${_REMOTE_USER}" != "root" ] && __users__add "${_REMOTE_USER}"
  fi

  if [ "${_include_container}" = "true" ] && [ -n "${_CONTAINER_USER:-}" ]; then
    [ "${_CONTAINER_USER}" != "root" ] && __users__add "${_CONTAINER_USER}"
  fi

  local _extra
  for _extra in "${_extra_users[@]+"${_extra_users[@]}"}"; do
    [ -n "$_extra" ] && __users__add "$_extra"
  done

  if [ "${_include_all}" = "true" ]; then
    local _min_uid=1000
    [ "$(os__kernel)" = "Darwin" ] && _min_uid=500
    local _passwd_uname _passwd_uid _passwd_shell
    __users__scan_all_line() {
      _passwd_uname="${1%%:*}"
      local _rest="${1#*:}"
      _rest="${_rest#*:}"
      _passwd_uid="${_rest%%:*}"
      _passwd_shell="${1##*:}"
      [ -z "$_passwd_uname" ] && return 0
      case "$_passwd_uid" in
        '' | *[!0-9]*) return 0 ;;
      esac
      [ "$_passwd_uid" -ge "$_min_uid" ] || return 0
      [ "$_passwd_uid" -lt 65534 ] || return 0
      case "$_passwd_shell" in
        */nologin | */false) return 0 ;;
      esac
      __users__add "$_passwd_uname"
    }
    local _pw_line
    if bootstrap__getent && command -v getent > /dev/null 2>&1; then
      while IFS= read -r _pw_line; do
        [ -n "$_pw_line" ] && __users__scan_all_line "$_pw_line"
      done <<< "$(getent passwd)"
    else
      while IFS= read -r _pw_line; do
        [ -n "$_pw_line" ] && __users__scan_all_line "$_pw_line"
      done < /etc/passwd
    fi
    unset -f __users__scan_all_line
  fi

  if [ "$_root_queued" = "true" ] && [ -z "$_out" ]; then
    __users__add "root"
  fi

  if [ -n "$_out" ]; then
    logging__info "resolved users='${_out# }'"
  else
    logging__info "resolved users='(empty)'"
  fi

  local _name
  for _name in $_out; do
    printf '%s\n' "$_name"
  done
  return 0
}

users__set_write_permissions() {
  # @brief users__set_write_permissions <prefix> <owner> <group> [<user>...] — Create OS group, add listed users, then apply group-write bits on a shared installation prefix.
  #
  # Sets the setgid bit on all subdirectories so new files inherit the group.
  # Uses dseditgroup on macOS and groupadd/usermod on Linux.
  #
  # Args:
  #   <prefix>     Absolute path to the installation directory.
  #   <owner>      Username of the primary file owner (chown target).
  #   <group>      OS group name to create (if absent) and use.
  #   [<user>...]  Additional users to add to the group.
  bootstrap__coreutils
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "coreutils is required to set write permissions."
    return "$_rc"
  }
  bootstrap__find || return 1
  local _path="$1" _owner="$2" _group="$3"
  shift 3
  logging__info "Setting write permissions on '${_path}' (owner: '${_owner}', group: '${_group}')."
  if command -v dseditgroup > /dev/null 2>&1; then
    dseditgroup -o read "$_group" > /dev/null 2>&1 || users__run_privileged dseditgroup -o create -q "$_group"
    local _u
    for _u in "$@"; do
      [ -z "$_u" ] && continue
      dseditgroup -o checkmember -m "$_u" "$_group" > /dev/null 2>&1 ||
        users__run_privileged dseditgroup -o edit -a "$_u" -t user "$_group"
    done
  else
    if bootstrap__shadow_utils; then
      getent group "$_group" > /dev/null 2>&1 || users__run_privileged groupadd -r "$_group"
      local _u
      for _u in "$@"; do
        [ -z "$_u" ] && continue
        id -nG "$_u" 2> /dev/null | grep -qw "$_group" && continue
        users__add_to_group "$_u" "$_group"
      done
    else
      logging__warn "Neither dseditgroup nor groupadd found — skipping group setup."
    fi
  fi
  logging__install "Applying owner '${_owner}' and group '${_group}' on '${_path}'."
  users__run_privileged chown -R "${_owner}:${_group}" "$_path" || {
    logging__error "Failed to chown '${_path}' to '${_owner}:${_group}'."
    return 1
  }
  users__run_privileged chmod -R g+rwX "$_path" || {
    logging__error "Failed to chmod group-write bits on '${_path}'."
    return 1
  }
  # Set the setgid bit on all subdirectories in one privileged find invocation.
  # The previous per-directory loop called sudo once per directory; on large
  # prefixes like /opt/homebrew this meant thousands of sudo invocations.
  # find -exec {} + batches paths into the fewest possible chmod calls.
  users__run_privileged find "$_path" -type d -exec chmod g+s {} + || {
    logging__error "Failed to set setgid bit on directories in '${_path}'."
    return 1
  }
  logging__success "Write permissions configured on '${_path}' (group '${_group}')."
  return 0
}

users__ensure_setuid() {
  # @brief users__ensure_setuid <binary>... — Locate each binary with `command -v` and set the setuid bit.
  #
  # Uses `command -v` for portable binary discovery across distros where binaries
  # may live in `/usr/bin`, `/usr/sbin`, or `/sbin` (e.g. `newuidmap`/`newgidmap`
  # on Fedora/RHEL/Alpine). Logs a warning when a binary is not found or `chmod`
  # fails, but does not abort.
  #
  # Args:
  #   <binary>...  One or more binary names (not full paths) to locate and set setuid on.
  #
  # Returns: 0 always (best-effort; individual failures are logged as warnings).
  local _bin _path
  for _bin in "$@"; do
    _path="$(command -v "$_bin" 2> /dev/null)" || true
    if [ -z "$_path" ]; then
      logging__warn "'${_bin}' not found on PATH — skipping setuid"
      continue
    fi
    if users__run_privileged chmod u+s "$_path"; then
      logging__info "set setuid on '${_path}'"
    else
      logging__warn "chmod u+s '${_path}' failed"
    fi
  done
  return 0
}

users__next_subid_offset() {
  # @brief users__next_subid_offset <file> — Print the next available subuid/subgid offset beyond all existing ranges in <file>.
  #
  # Scans every entry in <file> (format: `user:start:count`) and returns
  # `max(start + count)` across all entries, floored at 100000 (the
  # conventional minimum subordinate-ID starting point). This ensures a new
  # range appended immediately after the returned offset will never overlap
  # any pre-existing range — including ranges written by the base image or
  # other features.
  #
  # Args:
  #   <file>  Path to `/etc/subuid` or `/etc/subgid`.
  #
  # Stdout: next available offset (integer ≥ 100000).
  local _file="$1"
  local _max=100000
  local _user _start _count _end
  [ -f "$_file" ] || {
    printf '%s\n' "$_max"
    return 0
  }
  while IFS=: read -r _user _start _count; do
    # Skip comment lines and blank/malformed entries.
    case "$_user" in '#'* | '') continue ;; esac
    case "$_start" in '' | *[!0-9]*) continue ;; esac
    case "$_count" in '' | *[!0-9]*) continue ;; esac
    _end=$((_start + _count))
    [ "$_end" -gt "$_max" ] && _max="$_end"
  done < "$_file"
  printf '%s\n' "$_max"
  return 0
}

users__set_login_shell() {
  # @brief users__set_login_shell <shell_path> <username>... — Register `<shell_path>` in `/etc/shells`, patch Alpine PAM if needed, then call `chsh -s` for each user.
  #
  # Exits early with a warning (not an error) if chsh is not installed.
  # Skips users whose login shell is already set to <shell_path>. Logs a
  # warning when chsh fails for a user but does not abort.
  #
  # On Alpine: patches /etc/pam.d/chsh to allow root to run chsh without a
  # password (inserts "auth sufficient pam_rootok.so" if not already present).
  #
  # Args:
  #   <shell_path>   Absolute path to the shell binary (e.g. `/bin/zsh`).
  #   <username>...  One or more usernames to update.
  #
  # Returns: 0 on success (warnings logged for individual failures, not propagated).
  local _shell="$1"
  shift

  if ! ospkg__run --manifest "${_BOOTSTRAP__LIB_DIR}/deps/chsh.yaml" --build-group "lib-users"; then
    logging__warn "chsh not found — skipping shell change."
    return 0
  fi

  # Register the shell in /etc/shells. Guarded so a privilege failure (e.g. a
  # non-root user with no sudo can't write the system /etc/shells) warns and
  # continues rather than aborting the whole install — matching this function's
  # documented "warnings logged, not propagated" contract. chsh on one's own
  # login shell still works without the /etc/shells entry.
  local _shells_file=/etc/shells
  [ -f /usr/share/defaults/etc/shells ] && _shells_file=/usr/share/defaults/etc/shells
  if [ -f "$_shells_file" ] && ! grep -qx "$_shell" "$_shells_file" 2> /dev/null; then
    if printf '%s\n' "$_shell" | file__append_privileged "$_shells_file" 2> /dev/null; then
      logging__info "Added '${_shell}' to '${_shells_file}'."
    else
      logging__warn "Could not add '${_shell}' to '${_shells_file}' (no privilege); skipping."
    fi
  fi

  # Alpine PAM: chsh requires a password even when run as root unless
  # pam_rootok.so is listed as sufficient.
  if [ -f /etc/pam.d/chsh ]; then
    if ! grep -Eq '^auth[[:blank:]]+sufficient[[:blank:]]+pam_rootok\.so' /etc/pam.d/chsh 2> /dev/null; then
      if grep -Eq '^auth(.*)pam_rootok\.so' /etc/pam.d/chsh 2> /dev/null; then
        awk '/^auth(.*)pam_rootok\.so$/ { $2 = "sufficient" } { print }' \
          /etc/pam.d/chsh > /tmp/_chsh.tmp && users__run_privileged mv /tmp/_chsh.tmp /etc/pam.d/chsh
      else
        printf 'auth sufficient pam_rootok.so\n' | file__append_privileged /etc/pam.d/chsh
      fi
      logging__info "Fixed pam_rootok.so in /etc/pam.d/chsh."
    fi
  fi

  local _username _current_shell
  for _username in "$@"; do
    [ -z "$_username" ] && continue
    _current_shell="$(getent passwd "$_username" 2> /dev/null | cut -d: -f7 || true)"
    if [ "$_current_shell" = "$_shell" ]; then
      logging__info "Shell for '${_username}' already set to '${_shell}'."
      continue
    fi
    if users__run_privileged chsh -s "$_shell" "$_username"; then
      logging__success "Shell for '${_username}' set to '${_shell}'."
    else
      logging__warn "chsh failed for '${_username}'."
    fi
  done
  return 0
}

users__create_group() {
  # @brief users__create_group <name> [--gid <gid>] — Create a group, optionally with a specific GID.
  #
  # Args:
  #   <name>     Group name.
  #   --gid <n>  Numeric GID to assign (optional).
  #
  # Returns: 0 on success, 1 if groupadd cannot be installed.
  local _name="$1"
  shift
  local _gid=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --gid)
        _gid="$2"
        shift 2
        ;;
      *) shift ;;
    esac
  done
  bootstrap__shadow_utils
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "shadow-utils is required to create a group."
    return "$_rc"
  }
  local -a _cmd=("groupadd")
  [ -n "$_gid" ] && _cmd+=("--gid" "$_gid")
  _cmd+=("$_name")
  logging__install "Creating group '${_name}'${_gid:+ (gid=${_gid})}."
  users__run_privileged "${_cmd[@]}" || {
    logging__error "failed to create group '${_name}'."
    return 1
  }
}

users__delete_group() {
  # @brief users__delete_group <name> — Delete a group by name.
  #
  # Args:
  #   <name>  Group name to delete.
  #
  # Returns: 0 on success, 1 on failure (warning logged).
  bootstrap__shadow_utils
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "shadow-utils is required to delete a group."
    return "$_rc"
  }
  users__run_privileged groupdel "$1" 2> /dev/null || {
    logging__error "Failed to delete group '${1}'."
    return 1
  }
}

users__delete_user() {
  # @brief users__delete_user <name> — Delete a user account.
  #
  # Args:
  #   <name>  Username to delete.
  #
  # Returns: 0 on success, 1 on failure (warning logged).
  bootstrap__shadow_utils
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "shadow-utils is required to delete a user."
    return "$_rc"
  }
  users__run_privileged userdel "$1" 2> /dev/null || {
    logging__error "Failed to delete user '${1}'."
    return 1
  }
}

users__create_user() {
  # @brief users__create_user <name> [--uid <uid>] [--gid <gid>] [--home <path>] [--shell <shell>] [--no-create-home] — Create a regular user account.
  #
  # Unlike users__create_system_user, this creates a non-system user and does not
  # skip existing users — conflict resolution is left to the caller.
  #
  # Args:
  #   <name>            Login name.
  #   --uid <n>         Numeric UID (optional).
  #   --gid <n>         Numeric primary GID (optional).
  #   --home <path>     Home directory path (optional).
  #   --shell <shell>   Login shell (optional).
  #   --no-create-home  Do not create the home directory.
  #
  # Returns: 0 on success, 1 if useradd cannot be installed.
  local _name="$1"
  shift
  local _uid="" _gid="" _home="" _shell="" _no_create_home=false
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --uid)
        _uid="$2"
        shift 2
        ;;
      --gid)
        _gid="$2"
        shift 2
        ;;
      --home)
        _home="$2"
        shift 2
        ;;
      --shell)
        _shell="$2"
        shift 2
        ;;
      --no-create-home)
        _no_create_home=true
        shift
        ;;
      *) shift ;;
    esac
  done
  bootstrap__shadow_utils
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "shadow-utils is required to create a user."
    return "$_rc"
  }
  local -a _cmd=("useradd")
  [[ "$_no_create_home" == "true" ]] && _cmd+=("--no-create-home")
  [ -n "$_home" ] && _cmd+=("--home-dir" "$_home")
  [ -n "$_gid" ] && _cmd+=("--gid" "$_gid")
  [ -n "$_shell" ] && _cmd+=("--shell" "$_shell")
  [ -n "$_uid" ] && _cmd+=("--uid" "$_uid")
  _cmd+=("$_name")
  # shellcheck disable=SC2016
  logging__install "Creating user '${_name}'${_uid:+ (uid=${_uid})}${_home:+ (home='${_home}')}."
  users__run_privileged "${_cmd[@]}" || {
    logging__error "failed to create user '${_name}'."
    return 1
  }
}

users__add_to_group() {
  # @brief users__add_to_group <user> <group> — Add <user> to supplementary group <group>.
  #
  # Args:
  #   <user>   Username to modify.
  #   <group>  Group name to add the user to.
  #
  # Returns: 0 on success, 1 if usermod cannot be installed.
  local _user="$1" _group="$2"
  bootstrap__shadow_utils
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "shadow-utils is required to add a user to a group."
    return "$_rc"
  }
  users__run_privileged usermod -aG "$_group" "$_user" || {
    logging__warn "Failed to add '${_user}' to group '${_group}'."
    return 1
  }
}

users__create_system_user() {
  # @brief users__create_system_user <username> [--home <path>] [--shell <shell>] — Create a system user if it does not already exist.
  #
  # Ensures useradd is available, installing the appropriate shadow package if needed.
  # No-op if the user already exists.
  #
  # Args:
  #   <username>       Login name for the new user.
  #   --home <path>    Home directory. Optional.
  #   --shell <shell>  Login shell. Optional.
  #
  # Returns: 0 on success or if user already exists, 1 if useradd cannot be installed.
  bootstrap__coreutils
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "coreutils (id) is required to create a system user."
    return "$_rc"
  }
  local _username="$1"
  shift
  local _home="" _shell=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --home)
        _home="$2"
        shift 2
        ;;
      --shell)
        _shell="$2"
        shift 2
        ;;
      *) shift ;;
    esac
  done
  if id "$_username" > /dev/null 2>&1; then
    logging__info "User '${_username}' already exists — skipping."
    return 0
  fi
  bootstrap__shadow_utils
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "shadow-utils is required to create a system user."
    return "$_rc"
  }
  local -a _cmd=("useradd" "--system" "--create-home")
  [ -n "$_home" ] && _cmd+=("--home-dir" "$_home")
  [ -n "$_shell" ] && _cmd+=("--shell" "$_shell")
  _cmd+=("$_username")
  logging__install "Creating system user '${_username}'."
  users__run_privileged "${_cmd[@]}" || {
    logging__error "Failed to create system user '${_username}'."
    return 1
  }
  logging__success "Created system user '${_username}'."
  return 0
}

users__get_current() {
  # @brief users__get_current [--no-sudo] — Print the current username.
  #
  # Resolution order (default): SUDO_USER → devcontainer _REMOTE_USER (non-root) /
  # _CONTAINER_USER → id -un. coreutils is bootstrapped via ospkg when id is absent.
  #
  # Args:
  #   [--no-sudo]  Skip SUDO_USER / devcontainer vars and return the effective process owner.
  #
  # Stdout: username string.
  #
  # Returns: 0 on success, 1 if id cannot be made available.
  if [ "${1:-}" != "--no-sudo" ] && users__is_root; then
    if [ -n "${SUDO_USER:-}" ]; then
      printf '%s\n' "${SUDO_USER}"
      return 0
    fi
    if os__is_devcontainer_build; then
      if [ -n "${_REMOTE_USER:-}" ] && [ "${_REMOTE_USER}" != "root" ]; then
        printf '%s\n' "${_REMOTE_USER}"
        return 0
      fi
      [ -n "${_CONTAINER_USER:-}" ] && {
        printf '%s\n' "${_CONTAINER_USER}"
        return 0
      }
    fi
  fi
  bootstrap__coreutils
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "coreutils (id) is required to determine the current user."
    return "$_rc"
  }
  id -un
}

users__resolve_home() {
  # @brief users__resolve_home [--uid] [<username-or-uid>] — Print the home directory for the given user.
  #
  # Resolution order:
  #   1. `getent passwd` (bootstrapped if absent) — works for both usernames and
  #      UIDs; also queries NSS (LDAP, NIS).
  #   2. `dscl` on macOS (always available) — for Directory Services users absent from getent.
  #      For a UID: resolves the username via `dscl . -search` first.
  #   3. Direct `/etc/passwd` scan — last resort when the getent bootstrap failed
  #      Returns empty string when the user has no entry.
  #   4. Devcontainer env vars (`_REMOTE_USER_HOME` / `_CONTAINER_USER_HOME`) —
  #      used when all other methods return empty; in UID mode the UID is first
  #      resolved to a username via `users__username_of_uid`.
  #
  # When called with no positional argument, resolves the home of the current
  # user via `users__get_current`.
  #
  # Args:
  #   [--uid]   Treat the argument as a numeric UID rather than a username.
  #   [<value>] Username or numeric UID. Defaults to the current user (username).
  #
  # Stdout: absolute path to the home directory, or empty when no entry is found.
  # Returns: 0 on success, 1 if the no-arg form cannot determine the current user.
  local _by_uid=false
  if [[ "${1:-}" == "--uid" ]]; then
    _by_uid=true
    shift
  fi
  local _user="${1:-}" _entry="" _home
  if [[ -z "$_user" ]]; then
    _user="$(users__get_current)"
    local _rc=$?
    [[ $_rc == 0 ]] || {
      logging__error "could not determine current user for home resolution."
      return "$_rc"
    }
  fi
  # getent handles both username and UID, and queries NSS (LDAP, NIS).
  if bootstrap__getent && command -v getent > /dev/null 2>&1; then
    _entry="$(getent passwd "$_user" 2> /dev/null)"
    if [ -n "$_entry" ]; then
      IFS=: read -r _ _ _ _ _ _home _ <<< "$_entry"
      printf '%s\n' "$_home"
      return 0
    fi
  fi
  # macOS: users in Directory Services are absent from getent/passwd.
  if [[ "$(os__kernel)" == "Darwin" ]]; then
    local _uname="$_user"
    if [[ "$_by_uid" == true ]]; then
      _uname="$(dscl . -search /Users UniqueID "$_user" 2> /dev/null | awk 'NR==1{print $1}')"
    fi
    if [ -n "$_uname" ]; then
      _home="$(dscl . -read "/Users/${_uname}" NFSHomeDirectory 2> /dev/null | awk '{print $2}')"
      [ -n "$_home" ] && {
        printf '%s\n' "$_home"
        return 0
      }
    fi
  fi
  # Last resort: direct /etc/passwd scan when getent bootstrap failed (or dscl found nothing on macOS).
  [[ "$_by_uid" == true ]] && _home="$(awk -F: -v u="$_user" '$3==u{print $6;exit}' /etc/passwd 2> /dev/null)" ||
    _home="$(awk -F: -v u="$_user" '$1==u{print $6;exit}' /etc/passwd 2> /dev/null)"
  # Devcontainer: use the injected home env vars when all other lookups failed.
  if [ -z "$_home" ] && os__is_devcontainer_build; then
    local _uname="$_user"
    [[ "$_by_uid" == true ]] && _uname="$(users__username_of_uid "$_user" 2> /dev/null || true)"
    [ -n "$_uname" ] && [ "${_uname}" = "${_REMOTE_USER}" ] && _home="${_REMOTE_USER_HOME}"
    [ -z "$_home" ] && [ -n "$_uname" ] && [ "${_uname}" = "${_CONTAINER_USER}" ] && _home="${_CONTAINER_USER_HOME}"
  fi
  [[ "$_by_uid" == true ]] && printf '%s\n' "${_home:-}" || printf '%s\n' "${_home:-~${_user}}"
}

users__expand_path() {
  # @brief users__expand_path [--user <username>] <expr> — Expand tilde, $HOME, and env-var references in a path expression using the target user's login environment.
  #
  # Runs bash as the target user via users__run_as (su -l), giving access to the
  # user's full login environment: $HOME, $XDG_*, and any vars set in their profile.
  # All bash parameter expansion forms are supported: ${VAR}, ${VAR:-default}, etc.
  #
  # Fast path: expressions with no '$' and no leading '~' are returned as-is
  # without spawning a subprocess.
  #
  # Security: rejects expressions containing (, ), `, ;, &, |, newline, ", '
  # (prevents command substitution, process substitution, and command chaining).
  #
  # Args:
  #   --user <username>  User whose login environment to use. Defaults to the current user.
  #   --env KEY=VALUE    Extra variable to export into the expansion environment (repeatable).
  #                      Use for variables unavailable in the user's login shell, e.g. ZDOTDIR
  #                      (only set by zsh's .zshenv, not bash login shells).
  #   <expr>             Path expression to expand (e.g. ~/foo, $HOME/bar, ${XDG_CONFIG_HOME:-${HOME}/.config}/baz).
  #
  # Stdout: expanded absolute path followed by a newline.
  # Returns: 0 on success, 1 on validation failure or expansion error.
  local _user=""
  local -a _extra_envs=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --user)
        _user="$2"
        shift 2
        ;;
      --env)
        _extra_envs+=("$2")
        shift 2
        ;;
      --)
        shift
        break
        ;;
      -*)
        logging__error "unknown option: $1"
        return 1
        ;;
      *) break ;;
    esac
  done
  local _expr="${1-}"
  [[ -z "$_user" ]] && _user="$(users__get_current)"

  # Security: reject command-execution metacharacters while allowing all bash
  # parameter expansion forms (${VAR}, ${VAR:-default}, ${VAR:+value}, etc.).
  # This check must run before the fast path so that inputs like `cmd` (no '$'
  # or leading '~') are still validated.
  if [[ "$_expr" == *'('* || "$_expr" == *')'* || "$_expr" == *'`'* ||
    "$_expr" == *';'* || "$_expr" == *'&'* || "$_expr" == *'|'* ||
    "$_expr" == *$'\n'* ]]; then
    logging__error "expression contains unsafe characters: '${_expr}'"
    return 1
  fi

  # Fast path: no '$' and no '~' anywhere — already an absolute path or plain string.
  if [[ "$_expr" != *'$'* && "$_expr" != *'~'* ]]; then
    printf '%s\n' "$_expr"
    return 0
  fi

  # Run as the target user to evaluate the expression in their full login environment.
  # su -l sources /etc/profile and the user's ~/.profile / ~/.bash_profile, making
  # $HOME, $XDG_*, and all user-configured env vars available.
  # Tilde is pre-converted to $HOME because eval does not expand tilde in double-quoted strings.
  # shellcheck disable=SC2016
  users__run_as "$_user" -- "${_BASH_BIN:-bash}" -c '
    _e="$1"; shift
    while [[ $# -gt 0 ]]; do export "$1"; shift; done
    [[ "$_e" == "~"* ]] && _e="${HOME}${_e#\~}"
    _e="${_e// ~/ ${HOME}}"
    _e="${_e//\\/\\\\}"
    _e="${_e//\"/\\\"}"
    eval "printf \"%s\n\" \"${_e}\""
  ' -- "$_expr" "${_extra_envs[@]}"
}

users__expand_multi() {
  # @brief users__expand_multi [--user <username>] [--env KEY=VALUE]... -- <expr>... — Expand tilde, $HOME, and env-var references in MULTIPLE strings using at most ONE login-shell invocation for the whole batch.
  #
  # Same expansion power as users__expand_path (${VAR}, ${VAR:-default},
  # ${VAR:+val}, ~ expansion) but WITHOUT character rejection: command
  # substitution ($( and a backtick) is neutralized (treated as literal text)
  # rather than causing the whole input to be rejected, so this is safe for
  # values that legitimately contain characters users__expand_path forbids —
  # ERE regex patterns (which commonly use parentheses and |) and URIs (which
  # commonly use & and ; in query strings). Use users__expand_path instead for
  # a value that becomes a raw filesystem path.
  #
  # Batching matters because each login-shell invocation (`su -l`) sources the
  # target user's full profile (.bashrc, .bash_profile, /etc/profile), which
  # with common dev-environment initializers (nvm, rbenv, conda) can cost
  # tens to hundreds of milliseconds — expanding N related fields individually
  # would spawn N login shells; this spawns at most one for the entire batch.
  #
  # Fast path: when NONE of the inputs contain '$' or start with '~', the
  # whole batch is returned unexpanded with no subprocess spawned at all.
  #
  # Known limitation: a literal `$(` that must survive verbatim in the output
  # should be written as `\$(` in the input (same convention as the backtick
  # and `\` handling in users__expand_path).
  #
  # Args:
  #   --user <username>  User whose login environment to use. Defaults to the current user.
  #   --env KEY=VALUE    Extra variable to export into the expansion environment (repeatable).
  #   -- <expr>...       One or more strings to expand, in order.
  #
  # Stdout: NUL-separated results, one per <expr>, in the same order.
  #   Consume via: mapfile -d '' -t out < <(users__expand_multi -- "$a" "$b" "$c")
  #
  # Returns: 0 on success, 1 on expansion error.
  local _user=""
  local -a _extra_envs=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --user)
        _user="$2"
        shift 2
        ;;
      --env)
        _extra_envs+=("$2")
        shift 2
        ;;
      --)
        shift
        break
        ;;
      -*)
        logging__error "unknown option: $1"
        return 1
        ;;
      *) break ;;
    esac
  done
  local -a _all=("$@")
  [[ ${#_all[@]} -eq 0 ]] && return 0
  [[ -z "$_user" ]] && _user="$(users__get_current)"

  # Fast path: nothing in the batch needs expansion — skip the shell spawn entirely.
  local _s _any_needs=false
  for _s in "${_all[@]}"; do
    if [[ "$_s" == *'$'* || "$_s" == '~'* ]]; then
      _any_needs=true
      break
    fi
  done
  if ! $_any_needs; then
    for _s in "${_all[@]}"; do printf '%s\0' "$_s"; done
    return 0
  fi

  # Leading integer arg tells the inner script how many KEY=VALUE env-export
  # pairs follow, before the batch of expressions to expand — avoids any
  # ambiguity between "how many envs" and "how many expressions" (unlike
  # users__expand_path, which has only a single expression and can safely
  # treat "everything after the first arg" as env pairs).
  # shellcheck disable=SC2016
  users__run_as "$_user" -- "${_BASH_BIN:-bash}" -c '
    _n="$1"; shift
    while [[ "$_n" -gt 0 ]]; do export "$1"; shift; _n=$((_n - 1)); done
    for _e in "$@"; do
      [[ "$_e" == "~"* ]] && _e="${HOME}${_e#\~}"
      _e="${_e// ~/ ${HOME}}"
      _e="${_e//\\/\\\\}"
      _e="${_e//\`/\\\`}"
      _e="${_e//\$(/\\\$(}"
      _e="${_e//\"/\\\"}"
      eval "printf \"%s\\0\" \"${_e}\""
    done
  ' -- "${#_extra_envs[@]}" "${_extra_envs[@]}" "${_all[@]}"
}

users__expand_string() {
  # @brief users__expand_string [--user <username>] [--env KEY=VALUE]... <text> — Expand tilde, $HOME, and env-var references in a single string.
  #
  # Thin single-value convenience wrapper around users__expand_multi. See
  # users__expand_multi for the full expansion semantics and the rationale
  # for why it differs from users__expand_path.
  #
  # Args:
  #   --user <username>  User whose login environment to use. Defaults to the current user.
  #   --env KEY=VALUE    Extra variable to export into the expansion environment (repeatable).
  #   <text>             String to expand.
  #
  # Stdout: the expanded string (no trailing newline).
  #
  # Returns: 0 on success, 1 on expansion error.
  local -a _fwd=()
  while [[ $# -gt 1 ]]; do
    case "$1" in
      --user | --env)
        _fwd+=("$1" "$2")
        shift 2
        ;;
      *) break ;;
    esac
  done
  local -a _out
  mapfile -d '' -t _out < <(users__expand_multi "${_fwd[@]}" -- "${1-}")
  printf '%s' "${_out[0]-}"
}

users__nonroot_share_dir() {
  # @brief users__nonroot_share_dir <username> — Print <username>'s equivalent of _FEAT_SHARE_DIR_NONROOT.
  #
  # Generalizes the "per-user share directory" computation: substitutes the
  # target user's home directory for the current user's home prefix in
  # _FEAT_SHARE_DIR_NONROOT (which is always of the form
  # "${HOME}/.local/share/<namespace>/<feature-id>" — see metadata.shared.yaml).
  #
  # Deliberately resolves the current user's home via users__resolve_home
  # (no args), NOT by reading the $HOME environment variable directly: a
  # caller iterating over several target users commonly runs each one's
  # operations in a subshell with $HOME transiently exported to THAT user's
  # home (so plain shell tilde-expansion behaves correctly inside it) — if
  # this function read $HOME directly, it would strip the wrong prefix (or
  # none at all) once called from inside such a subshell, silently producing
  # a garbled path. users__resolve_home's no-arg form instead re-derives the
  # true current identity (SUDO_USER / devcontainer vars / id -un), which
  # such a subshell override does not affect.
  #
  # Args:
  #   <username>  Target username.
  #
  # Stdout: absolute path to <username>'s equivalent share directory.
  #
  # Returns: 0 on success, 1 if the user's home or _FEAT_SHARE_DIR_NONROOT cannot be resolved.
  local _username="${1-}"
  [[ -n "$_username" ]] || {
    logging__error "users__nonroot_share_dir: username is required."
    return 1
  }
  [[ -n "${_FEAT_SHARE_DIR_NONROOT:-}" ]] || {
    logging__error "users__nonroot_share_dir: _FEAT_SHARE_DIR_NONROOT is not set."
    return 1
  }
  local _home
  _home="$(users__resolve_home "$_username")"
  [[ -n "$_home" ]] || {
    logging__error "users__nonroot_share_dir: cannot resolve home directory for '${_username}'."
    return 1
  }
  local _current_home
  _current_home="$(users__resolve_home)"
  local _suffix="${_FEAT_SHARE_DIR_NONROOT#"${_current_home}"}"
  printf '%s\n' "${_home}${_suffix}"
}

users__is_user_path() {
  # @brief users__is_user_path [--uid] [<username-or-uid>] <path> — Return 0 if <path> is user-local, 1 if it is system (requires privilege).
  #
  # "User-local" means writable by a regular user without elevated privileges.
  # Regular-user UID range is OS-specific: ≥1000 on Linux, ≥500 on macOS
  # (Apple reserves 0–499 for system accounts).
  # Uses the nearest existing ancestor of <path>, so the path itself need not exist yet.
  #
  # Without a user argument:
  #   - Non-root: user-local iff the current user can write without sudo.
  #   - Root: user-local iff under root's home or owned by a regular user.
  #
  # With a user argument, the check is against that specific user regardless of
  # who is running the script:
  #   - User-local iff the path is under that user's home directory, or the
  #     nearest existing ancestor is owned by that user.
  #
  # Args:
  #   [--uid]              Treat <username-or-uid> as a numeric UID rather than a username.
  #   [<username-or-uid>]  User to check against. Defaults to the current user.
  #   <path>               Absolute path to classify (need not exist).
  #
  # Returns: 0 (user-local/unprivileged), 1 (system/privileged).
  local _by_uid=false
  if [[ "${1:-}" == "--uid" ]]; then
    _by_uid=true
    shift
  fi
  local _p _user=""
  if [[ $# -ge 2 ]]; then
    _user="$1"
    shift
  fi
  _p="$1"
  local _existing
  _existing="$(file__nearest_existing "$_p")"
  if [[ -z "$_user" ]]; then
    # No user: runtime writability check (current user / root heuristic).
    if ! users__is_root; then
      [ -w "$_existing" ] && return 0
      return 1
    fi
    # Root: user-local iff under root's home or owned by a regular user.
    local _root_home
    _root_home="$(users__resolve_home)"
    [[ -n "$_root_home" && "$_p" == "${_root_home}/"* ]] && return 0
    local _uid _min_uid
    _uid="$(users__uid_of_path_owner "$_existing")"
    local _rc=$?
    [[ $_rc == 0 ]] || {
      logging__error "could not determine owner UID of '${_existing}'."
      return "$_rc"
    }
    [[ "$(os__kernel)" == "Darwin" ]] && _min_uid=500 || _min_uid=1000
    ((_uid >= _min_uid && _uid < 65534)) && return 0
    return 1
  fi
  # Specific user: deterministic identity-based check.
  local _home="" _target_uid=""
  if [[ "$_by_uid" == true ]]; then
    _target_uid="$_user"
    _home="$(users__resolve_home --uid "$_user")"
  else
    _home="$(users__resolve_home "$_user")"
    _target_uid="$(users__uid_of_user "$_user" 2> /dev/null)" || true
  fi
  # Under user's home directory.
  [[ -n "$_home" && "$_p" == "${_home}/"* ]] && return 0
  # Nearest existing ancestor owned by the user.
  if [[ -n "$_target_uid" ]]; then
    local _owner_uid
    _owner_uid="$(users__uid_of_path_owner "$_existing")"
    local _rc=$?
    [[ $_rc == 0 ]] || {
      logging__error "could not determine owner UID of '${_existing}'."
      return "$_rc"
    }
    [[ "$_owner_uid" == "$_target_uid" ]] && return 0
  fi
  return 1
}

users__add_sudoer() {
  # @brief users__add_sudoer <username> [--sudoers-dir <dir>] — Grant passwordless sudo to <username>.
  #
  # Writes "<username> ALL=(ALL) NOPASSWD:ALL" as a drop-in sudoers file.
  # Validates the file with visudo before moving it into place; on validation
  # failure the temporary file is removed and the function returns 1 without
  # touching the sudoers directory. Installs sudo via ospkg if absent.
  #
  # Args:
  #   <username>           User to grant passwordless sudo access.
  #   --sudoers-dir <dir>  Drop-in directory (default: /etc/sudoers.d).
  #
  # Returns: 0 on success, 1 on failure.
  local _username="${1:?users__add_sudoer: username is required}"
  local _sudoers_dir="/etc/sudoers.d"
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --sudoers-dir)
        _sudoers_dir="${2:?--sudoers-dir requires a value}"
        shift 2
        ;;
      *)
        logging__error "unknown option: '$1'"
        return 1
        ;;
    esac
  done
  bootstrap__sudo
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "sudo is required to grant passwordless sudo."
    return "$_rc"
  }
  local _target="${_sudoers_dir}/${_username}" _tmp _visudo_out
  _tmp="$(mktemp)" || {
    logging__error "mktemp failed."
    return 1
  }
  printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$_username" > "$_tmp"
  chmod 0440 "$_tmp"
  _visudo_out="$(users__run_privileged visudo -c -f "$_tmp" 2>&1)"
  local _rc=$?
  if [[ $_rc != 0 ]]; then
    rm -f "$_tmp"
    logging__error "sudoers validation failed${_visudo_out:+: ${_visudo_out}}"
    return "$_rc"
  fi
  users__run_privileged mkdir -p "$_sudoers_dir"
  users__run_privileged mv "$_tmp" "$_target"
  logging__success "Granted passwordless sudo to '${_username}'."
}

users__first_writeable_path() {
  # @brief users__first_writeable_path -- [<yaml-when>] path ... [-- ...] — First writable path from conditional groups.
  #
  # Groups separated by `--`. Optional first token in a group (if not an absolute path) is a YAML when blob.
  # Reads feat.* / plat.* / os.* from the global ctx registry (template ctx__set publish points).
  local -a _when _paths
  while [[ $# -gt 0 ]]; do
    [[ "$1" != "--" ]] && {
      shift
      continue
    }
    shift
    _when=()
    _paths=()
    while [[ $# -gt 0 && "$1" != "--" ]]; do
      if [[ ${#_paths[@]} -eq 0 && ${#_when[@]} -eq 0 && "$1" != /* && "$1" == *:* ]]; then
        _when+=("$1")
      else
        _paths+=("$1")
      fi
      shift
    done
    if [[ ${#_when[@]} -gt 0 ]]; then
      ctx__match_spec "${_when[0]}" || continue
    fi
    local _p
    for _p in "${_paths[@]}"; do
      if users__can_write "$_p"; then
        printf '%s\n' "$_p"
        return 0
      fi
    done
    logging__error "Prefix auto-resolution failed: no writable path found (tried: ${_paths[*]})."
    return 1
  done
  logging__error "Prefix auto-resolution failed: no platform group matched."
  return 1
}
