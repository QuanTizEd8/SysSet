#!/bin/sh
# shellcheck disable=SC3043  # 'local' is not POSIX but is supported by all targeted shells (dash, ash, macOS sh)
# POSIX sh compatible — safe to source from sh and bash scripts alike.
# Do not edit _lib/ copies directly — edit lib/ instead.
#
# users__set_login_shell uses awk and shell utilities available on all
# supported platforms (Debian, Alpine, macOS).

[ -n "${_USERS__LIB_LOADED-}" ] && return 0
_USERS__LIB_LOADED=1

# @brief users__resolve_list — Print one deduplicated username per line from devcontainer user-config env vars.
#
# Root is excluded from auto-detected paths (SUDO_USER, _REMOTE_USER,
# _CONTAINER_USER) when other non-root users exist, because the build process
# running as root should not override a named container user. When the build
# user IS root and no other users are found, root is included as a fallback
# (e.g. plain container images, standalone macOS use). Root is always
# accepted in ADD_USERS.
#
# Env vars consumed (all optional):
#   ADD_CURRENT_USER   — "true" to include SUDO_USER / whoami (default: true)
#   ADD_REMOTE_USER    — "true" to include _REMOTE_USER (default: true)
#   ADD_CONTAINER_USER — "true" to include _CONTAINER_USER (default: true)
#   ADD_USERS          — extra usernames (bash array, newline-delimited string,
#                        or comma-separated string); root allowed here
#
# Stdout: one username per line.
#
# Usage (bash — collect into array):
#   mapfile -t _users < <(users__resolve_list)
# Usage (POSIX sh — iterate):
#   users__resolve_list | while IFS= read -r _u; do ...; done
users__resolve_list() {
  # Track seen names in a local space-separated string for dedup.
  local _seen=""
  local _out=""
  local _raw_add_users="${ADD_USERS-}"

  echo "ℹ️  users__resolve_list: inputs ADD_CURRENT_USER='${ADD_CURRENT_USER:-true}' ADD_REMOTE_USER='${ADD_REMOTE_USER:-true}' ADD_CONTAINER_USER='${ADD_CONTAINER_USER:-true}' SUDO_USER='${SUDO_USER-}' _REMOTE_USER='${_REMOTE_USER-}' _CONTAINER_USER='${_CONTAINER_USER-}' _REMOTE_USER_HOME='${_REMOTE_USER_HOME-}' _CONTAINER_USER_HOME='${_CONTAINER_USER_HOME-}' ADD_USERS='${_raw_add_users}'" >&2

  _users_add() {
    local _name="$1"
    [ -z "$_name" ] && return 0
    case " ${_seen} " in
      *" ${_name} "*) return 0 ;;
    esac
    _seen="${_seen} ${_name}"
    _out="${_out} ${_name}"
    return 0
  }

  # Accept both newline and comma separators in scalar values.
  _users_add_from_text() {
    local _raw="$1"
    [ -z "$_raw" ] && return 0

    local _normalized _old_ifs _extra
    _normalized="$(printf '%s\n' "$_raw" | tr ',' '\n')"
    _old_ifs="$IFS"
    IFS='
'
    for _extra in $_normalized; do
      # Trim leading/trailing spaces.
      _extra="${_extra#"${_extra%%[! ]*}"}"
      _extra="${_extra%"${_extra##*[! ]}"}"
      _users_add "$_extra"
    done
    IFS="$_old_ifs"
    return 0
  }

  # Auto-detected users: root is deferred — only added as a fallback when
  # no other user is found.  In a devcontainer with a remoteUser/containerUser
  # the build runs as root, but configuration should target the named user, not
  # root.  When there is genuinely no other user (e.g. a plain container image
  # with no remoteUser or a standalone macOS install), root is the intended
  # target and should be included.
  local _root_queued=false
  if [ "${ADD_CURRENT_USER:-true}" = "true" ]; then
    local _cur="${SUDO_USER:-$(whoami)}"
    if [ "$_cur" != "root" ]; then
      _users_add "$_cur"
    else
      _root_queued=true
    fi
  fi

  if [ "${ADD_REMOTE_USER:-true}" = "true" ] && [ -n "${_REMOTE_USER:-}" ]; then
    [ "${_REMOTE_USER}" != "root" ] && _users_add "${_REMOTE_USER}"
  fi

  if [ "${ADD_CONTAINER_USER:-true}" = "true" ] && [ -n "${_CONTAINER_USER:-}" ]; then
    [ "${_CONTAINER_USER}" != "root" ] && _users_add "${_CONTAINER_USER}"
  fi

  # ADD_USERS: explicit override list — root is allowed if deliberately
  # specified (e.g. configuring Podman rootless for the root user).
  # The generated argparse header provides arrays in bash; support that first,
  # then fall back to scalar parsing for POSIX sh callers.
  if [ -n "${ADD_USERS:-}" ]; then
    if [ -n "${BASH_VERSION-}" ]; then
      local _bash_items
      # In bash, this safely serialises both scalar and array values.
      _bash_items="$(eval 'printf "%s\n" "${ADD_USERS[@]}"' 2> /dev/null || true)"
      _users_add_from_text "$_bash_items"
    else
      _users_add_from_text "${ADD_USERS}"
    fi
  fi

  # Root fallback: if the build user was root and no other users were resolved,
  # include root so the feature has a target to configure.
  if [ "$_root_queued" = "true" ] && [ -z "$_out" ]; then
    _users_add "root"
  fi

  # Log final result (or explicit empty marker) to aid CI debugging.
  if [ -n "$_out" ]; then
    echo "ℹ️  users__resolve_list: resolved users='${_out# }'" >&2
  else
    echo "ℹ️  users__resolve_list: resolved users='(empty)'" >&2
  fi

  # Print one name per line (strip leading space from _out).
  local _name
  for _name in $_out; do
    printf '%s\n' "$_name"
  done
  return 0
}

# @brief users__set_write_permissions <prefix> <owner> <group> [<user>...]
#   Create OS group, add listed users to it, then apply group-write bits on
#   a shared installation prefix so group members can install packages.
#
#   Sets the setgid bit on all subdirectories so new files inherit the group.
#   No-op on platforms that lack groupadd/usermod (e.g. macOS — log a warning).
#
# Args:
#   <prefix>    Absolute path to the installation directory.
#   <owner>     Username of the primary file owner (chown target).
#   <group>     OS group name to create (if absent) and use.
#   [<user>...] Additional users to add to the group.
users__set_write_permissions() {
  local _prefix="$1"
  local _owner="$2"
  local _group="$3"
  shift 3
  if ! command -v groupadd > /dev/null 2>&1; then
    echo "⚠️  groupadd not found — skipping write-permission setup." >&2
    return 0
  fi
  echo "🔐 Setting write permissions on '${_prefix}' (owner: '${_owner}', group: '${_group}')." >&2
  getent group "$_group" > /dev/null 2>&1 || groupadd -r "$_group"
  local _u
  for _u in "$@"; do
    [ -z "$_u" ] && continue
    id -nG "$_u" 2> /dev/null | grep -qw "$_group" || usermod -a -G "$_group" "$_u"
  done
  chown -R "${_owner}:${_group}" "$_prefix"
  chmod -R g+rwX "$_prefix"
  find "$_prefix" -type d -print0 | xargs -0 chmod g+s
  return 0
}

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
#   <shell_path>    Absolute path to the shell binary (e.g. /bin/zsh).
#   <username>...   One or more usernames to update.
users__set_login_shell() {
  local _shell="$1"
  shift

  if ! command -v chsh > /dev/null 2>&1; then
    echo "⚠️  chsh not found — skipping shell change. Install the 'passwd' package." >&2
    return 0
  fi

  # Register the shell in /etc/shells.
  local _shells_file=/etc/shells
  [ -f /usr/share/defaults/etc/shells ] && _shells_file=/usr/share/defaults/etc/shells
  if [ -f "$_shells_file" ] && ! grep -qx "$_shell" "$_shells_file" 2> /dev/null; then
    echo "$_shell" >> "$_shells_file"
    echo "ℹ️  Added '${_shell}' to '${_shells_file}'." >&2
  fi

  # Alpine PAM: chsh requires a password even when run as root unless
  # pam_rootok.so is listed as sufficient.
  if [ -f /etc/pam.d/chsh ]; then
    if ! grep -Eq '^auth[[:blank:]]+sufficient[[:blank:]]+pam_rootok\.so' /etc/pam.d/chsh 2> /dev/null; then
      if grep -Eq '^auth(.*)pam_rootok\.so' /etc/pam.d/chsh 2> /dev/null; then
        awk '/^auth(.*)pam_rootok\.so$/ { $2 = "sufficient" } { print }' \
          /etc/pam.d/chsh > /tmp/_chsh.tmp && mv /tmp/_chsh.tmp /etc/pam.d/chsh
      else
        printf 'auth sufficient pam_rootok.so\n' >> /etc/pam.d/chsh
      fi
      echo "ℹ️  Fixed pam_rootok.so in /etc/pam.d/chsh." >&2
    fi
  fi

  for _username in "$@"; do
    [ -z "$_username" ] && continue
    _current_shell="$(getent passwd "$_username" 2> /dev/null | cut -d: -f7 || true)"
    if [ "$_current_shell" = "$_shell" ]; then
      echo "ℹ️  Shell for '${_username}' already set to '${_shell}'." >&2
      continue
    fi
    if chsh -s "$_shell" "$_username" 2> /dev/null; then
      echo "✅ Shell for '${_username}' set to '${_shell}'." >&2
    else
      echo "⚠️  chsh failed for '${_username}'." >&2
    fi
  done
  return 0
}
