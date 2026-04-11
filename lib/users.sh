#!/bin/sh
# POSIX sh compatible — safe to source from sh and bash scripts alike.
# Do not edit _lib/ copies directly — edit lib/ instead.
#
# users::set_login_shell uses awk and shell utilities available on all
# supported platforms (Debian, Alpine, macOS).

[ -n "${_LIB_USERS_LOADED-}" ] && return 0
_LIB_USERS_LOADED=1

# users::resolve_list
#
# Reads the standard devcontainer user-config env vars and prints one
# deduplicated username per line to stdout.
#
# Root is excluded from auto-detected paths (CURRENT_USER, REMOTE_USER,
# CONTAINER_USER) since the build user running as root is not a target user.
# Root IS included when explicitly listed in ADD_USER_CONFIG.
#
# Env vars consumed (all optional):
#   ADD_CURRENT_USER_CONFIG   — "true" to include SUDO_USER / whoami (default: true)
#   ADD_REMOTE_USER_CONFIG    — "true" to include _REMOTE_USER (default: true)
#   ADD_CONTAINER_USER_CONFIG — "true" to include _CONTAINER_USER (default: true)
#   ADD_USER_CONFIG           — comma-separated extra usernames; root allowed here
#
# Usage (bash caller — collect into array):
#   mapfile -t _RESOLVED_USERS < <(users::resolve_list)
#
# Usage (POSIX sh caller — iterate):
#   users::resolve_list | while IFS= read -r _u; do ...; done
users::resolve_list() {
  # Track seen names in a local space-separated string for dedup.
  local _seen=""
  local _out=""

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

  # Auto-detected users: skip root (the build user running as root is not a
  # target user for shell/tool configuration).
  if [ "${ADD_CURRENT_USER_CONFIG:-true}" = "true" ]; then
    local _cur="${SUDO_USER:-$(whoami)}"
    [ "$_cur" != "root" ] && _users_add "$_cur"
  fi

  if [ "${ADD_REMOTE_USER_CONFIG:-true}" = "true" ] && [ -n "${_REMOTE_USER:-}" ]; then
    [ "${_REMOTE_USER}" != "root" ] && _users_add "${_REMOTE_USER}"
  fi

  if [ "${ADD_CONTAINER_USER_CONFIG:-true}" = "true" ] && [ -n "${_CONTAINER_USER:-}" ]; then
    [ "${_CONTAINER_USER}" != "root" ] && _users_add "${_CONTAINER_USER}"
  fi

  # ADD_USER_CONFIG: explicit override list — root is allowed if deliberately
  # specified (e.g. configuring Podman rootless for the root user).
  if [ -n "${ADD_USER_CONFIG:-}" ]; then
    local _old_ifs="$IFS"
    IFS=','
    for _extra in ${ADD_USER_CONFIG}; do
      # Trim leading/trailing spaces.
      _extra="${_extra#"${_extra%%[! ]*}"}"
      _extra="${_extra%"${_extra##*[! ]}"}"
      _users_add "$_extra"
    done
    IFS="$_old_ifs"
  fi

  # Print one name per line (strip leading space from _out).
  local _name
  for _name in $_out; do
    printf '%s\n' "$_name"
  done
  return 0
}

# users::set_login_shell <shell_path> <username>...
#
# Sets the login shell for one or more users.
#   • Ensures <shell_path> is registered in /etc/shells (idempotent).
#   • On Alpine, patches /etc/pam.d/chsh to allow root to run chsh without a
#     password (inserts "auth sufficient pam_rootok.so" if not present).
#   • Calls chsh -s <shell_path> for each user; skips users already on that
#     shell; logs a warning when chsh fails but does not abort.
# Exits early (with a warning, not an error) if chsh is not installed.
users::set_login_shell() {
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
