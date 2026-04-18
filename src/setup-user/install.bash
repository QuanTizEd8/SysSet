#!/usr/bin/env bash
set -euo pipefail

_SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
_BASE_DIR="$_SELF_DIR"

# shellcheck source=lib/ospkg.sh
. "$_SELF_DIR/_lib/ospkg.sh"
# shellcheck source=lib/logging.sh
. "$_SELF_DIR/_lib/logging.sh"
logging__setup
echo "↪️ Script entry: User Setup" >&2
# Override _cleanup_hook in the hand-written section for feature-specific
# cleanup (e.g. removing temp files). Do NOT call logging__cleanup there;
# _on_exit owns that call and guarantees it runs exactly once, last.
# shellcheck disable=SC2329
_cleanup_hook() { return; }
# shellcheck disable=SC2329
_on_exit() {
  local _rc=$?
  _cleanup_hook
  [[ "${KEEP_CACHE:-true}" != true ]] && ospkg__clean
  if [[ $_rc -eq 0 ]]; then
    echo "✅ User Setup script finished successfully." >&2
  else
    echo "❌ User Setup script exited with error ${_rc}." >&2
  fi
  logging__cleanup
  return
}
trap '_on_exit' EXIT

__usage__() {
  cat << 'EOF'
Usage: install.bash [OPTIONS]

Options:
  --username <value>                    Username to create. (default: "vscode")
  --user_id <value>                     UID to assign to the user. Must be a non-negative integer. (default: "1000")
  --group_id <value>                    GID to assign to the user's primary group. Must be a non-negative integer. (default: "1000")
  --group_name <value>                  Name for the user's primary group. Defaults to the `username` when left empty.
  --home_dir <value>                    Home directory for the user. Defaults to `/home/<username>` when left empty.
  --user_shell <value>                  Login shell for the user. The path must exist and be executable on the image. (default: "/bin/bash")
  --sudo_access {true,false}            Grant the user passwordless `sudo` access. Installs `sudo` if not already present. (default: "true")
  --extra_groups <value>  (repeatable)  Supplementary groups to add the user to. Groups must already exist.
  --replace_existing {true,false}       When true, any user or group occupying the requested UID/GID is removed first (home directories are preserved). When false, a conflict causes the script to fail unless the user is already correctly configured. (default: "true")
  --sudoers_dir <value>                 Directory for the sudoers drop-in file. (default: "/etc/sudoers.d")
  --keep_cache {true,false}             Keep the package manager cache after installation. By default, the package manager cache is removed after installation to reduce image layer size. Set this flag to true to keep the cache, which may speed up subsequent installations at the cost of larger image layers. (default: "false")
  --debug {true,false}                  Enable debug output. This adds `set -x` to the installer script, which prints each command before executing it. (default: "false")
  --logfile <value>                     Log all output (stdout + stderr) to this file in addition to console.
  -h, --help                            Show this help
EOF
  return
}

if [ "$#" -gt 0 ]; then
  echo "ℹ️ Script called with arguments: $*" >&2
  USERNAME="vscode"
  USER_ID="1000"
  GROUP_ID="1000"
  GROUP_NAME=""
  HOME_DIR=""
  USER_SHELL="/bin/bash"
  SUDO_ACCESS=true
  EXTRA_GROUPS=()
  REPLACE_EXISTING=true
  SUDOERS_DIR="/etc/sudoers.d"
  KEEP_CACHE=false
  DEBUG=false
  LOGFILE=""
  while [ "$#" -gt 0 ]; do
    case $1 in
      --username)
        shift
        USERNAME="$1"
        echo "📩 Read argument 'username': '${USERNAME}'" >&2
        shift
        ;;
      --user_id)
        shift
        USER_ID="$1"
        echo "📩 Read argument 'user_id': '${USER_ID}'" >&2
        shift
        ;;
      --group_id)
        shift
        GROUP_ID="$1"
        echo "📩 Read argument 'group_id': '${GROUP_ID}'" >&2
        shift
        ;;
      --group_name)
        shift
        GROUP_NAME="$1"
        echo "📩 Read argument 'group_name': '${GROUP_NAME}'" >&2
        shift
        ;;
      --home_dir)
        shift
        HOME_DIR="$1"
        echo "📩 Read argument 'home_dir': '${HOME_DIR}'" >&2
        shift
        ;;
      --user_shell)
        shift
        USER_SHELL="$1"
        echo "📩 Read argument 'user_shell': '${USER_SHELL}'" >&2
        shift
        ;;
      --sudo_access)
        shift
        SUDO_ACCESS="$1"
        echo "📩 Read argument 'sudo_access': '${SUDO_ACCESS}'" >&2
        shift
        ;;
      --extra_groups)
        shift
        EXTRA_GROUPS+=("$1")
        echo "📩 Read argument 'extra_groups': '$1'" >&2
        shift
        ;;
      --replace_existing)
        shift
        REPLACE_EXISTING="$1"
        echo "📩 Read argument 'replace_existing': '${REPLACE_EXISTING}'" >&2
        shift
        ;;
      --sudoers_dir)
        shift
        SUDOERS_DIR="$1"
        echo "📩 Read argument 'sudoers_dir': '${SUDOERS_DIR}'" >&2
        shift
        ;;
      --keep_cache)
        shift
        KEEP_CACHE="$1"
        echo "📩 Read argument 'keep_cache': '${KEEP_CACHE}'" >&2
        shift
        ;;
      --debug)
        shift
        DEBUG="$1"
        echo "📩 Read argument 'debug': '${DEBUG}'" >&2
        shift
        ;;
      --logfile)
        shift
        LOGFILE="$1"
        echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2
        shift
        ;;
      -h | --help)
        __usage__
        exit 0
        ;;
      --*)
        echo "⛔ Unknown option: '${1}'" >&2
        exit 1
        ;;
      *)
        echo "⛔ Unexpected argument: '${1}'" >&2
        exit 1
        ;;
    esac
  done
else
  echo "ℹ️ Script called with no arguments. Read environment variables." >&2
  [ "${USERNAME+defined}" ] && echo "📩 Read argument 'username': '${USERNAME}'" >&2
  [ "${USER_ID+defined}" ] && echo "📩 Read argument 'user_id': '${USER_ID}'" >&2
  [ "${GROUP_ID+defined}" ] && echo "📩 Read argument 'group_id': '${GROUP_ID}'" >&2
  [ "${GROUP_NAME+defined}" ] && echo "📩 Read argument 'group_name': '${GROUP_NAME}'" >&2
  [ "${HOME_DIR+defined}" ] && echo "📩 Read argument 'home_dir': '${HOME_DIR}'" >&2
  [ "${USER_SHELL+defined}" ] && echo "📩 Read argument 'user_shell': '${USER_SHELL}'" >&2
  [ "${SUDO_ACCESS+defined}" ] && echo "📩 Read argument 'sudo_access': '${SUDO_ACCESS}'" >&2
  if [ "${EXTRA_GROUPS+defined}" ]; then
    if [ -n "${EXTRA_GROUPS-}" ]; then
      mapfile -t EXTRA_GROUPS < <(printf '%s\n' "${EXTRA_GROUPS}" | grep -v '^$')
      for _item in "${EXTRA_GROUPS[@]}"; do
        echo "📩 Read argument 'extra_groups': '$_item'" >&2
      done
    else
      EXTRA_GROUPS=()
    fi
  fi
  [ "${REPLACE_EXISTING+defined}" ] && echo "📩 Read argument 'replace_existing': '${REPLACE_EXISTING}'" >&2
  [ "${SUDOERS_DIR+defined}" ] && echo "📩 Read argument 'sudoers_dir': '${SUDOERS_DIR}'" >&2
  [ "${KEEP_CACHE+defined}" ] && echo "📩 Read argument 'keep_cache': '${KEEP_CACHE}'" >&2
  [ "${DEBUG+defined}" ] && echo "📩 Read argument 'debug': '${DEBUG}'" >&2
  [ "${LOGFILE+defined}" ] && echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2
fi

[[ "${DEBUG:-}" == true ]] && set -x

# Apply defaults.
[ "${USERNAME+defined}" ] || {
  USERNAME="vscode"
  echo "ℹ️ Argument 'username' set to default value 'vscode'." >&2
}
[ "${USER_ID+defined}" ] || {
  USER_ID="1000"
  echo "ℹ️ Argument 'user_id' set to default value '1000'." >&2
}
[ "${GROUP_ID+defined}" ] || {
  GROUP_ID="1000"
  echo "ℹ️ Argument 'group_id' set to default value '1000'." >&2
}
[ "${GROUP_NAME+defined}" ] || {
  GROUP_NAME=""
  echo "ℹ️ Argument 'group_name' set to default value ''." >&2
}
[ "${HOME_DIR+defined}" ] || {
  HOME_DIR=""
  echo "ℹ️ Argument 'home_dir' set to default value ''." >&2
}
[ "${USER_SHELL+defined}" ] || {
  USER_SHELL="/bin/bash"
  echo "ℹ️ Argument 'user_shell' set to default value '/bin/bash'." >&2
}
[ "${SUDO_ACCESS+defined}" ] || {
  SUDO_ACCESS=true
  echo "ℹ️ Argument 'sudo_access' set to default value 'true'." >&2
}
[ "${EXTRA_GROUPS+defined}" ] || {
  EXTRA_GROUPS=()
  echo "ℹ️ Argument 'extra_groups' set to default value '(empty)'." >&2
}
[ "${REPLACE_EXISTING+defined}" ] || {
  REPLACE_EXISTING=true
  echo "ℹ️ Argument 'replace_existing' set to default value 'true'." >&2
}
[ "${SUDOERS_DIR+defined}" ] || {
  SUDOERS_DIR="/etc/sudoers.d"
  echo "ℹ️ Argument 'sudoers_dir' set to default value '/etc/sudoers.d'." >&2
}
[ "${KEEP_CACHE+defined}" ] || {
  KEEP_CACHE=false
  echo "ℹ️ Argument 'keep_cache' set to default value 'false'." >&2
}
[ "${DEBUG+defined}" ] || {
  DEBUG=false
  echo "ℹ️ Argument 'debug' set to default value 'false'." >&2
}
[ "${LOGFILE+defined}" ] || {
  LOGFILE=""
  echo "ℹ️ Argument 'logfile' set to default value ''." >&2
}

ospkg__run --manifest "${_BASE_DIR}/dependencies/base.yaml" --skip_installed

# END OF AUTOGENERATED BLOCK

os__require_root

if [[ ! "$USER_ID" =~ ^[0-9]+$ ]]; then
  echo "⛔ user_id must be a non-negative integer, got: '${USER_ID}'" >&2
  exit 1
fi

if [[ ! "$GROUP_ID" =~ ^[0-9]+$ ]]; then
  echo "⛔ group_id must be a non-negative integer, got: '${GROUP_ID}'" >&2
  exit 1
fi

if [ ! -x "$USER_SHELL" ]; then
  echo "⛔ Shell '${USER_SHELL}' does not exist or is not executable on this image." >&2
  exit 1
fi

# Values derived from USERNAME
[ -z "$GROUP_NAME" ] && GROUP_NAME="$USERNAME"
[ -z "$HOME_DIR" ] && HOME_DIR="/home/${USERNAME}"

# ---------------------------------------------------------------------------
# Resolve conflicts for the primary group
# ---------------------------------------------------------------------------

_group_already_ok=false
_group_by_gid=$(getent group | awk -F: -v gid="$GROUP_ID" '$3 == gid {print $1}' || true)
_gid_of_name=$(getent group "$GROUP_NAME" 2> /dev/null | cut -d: -f3 || true)

if [ -n "$_gid_of_name" ] && [ "$_gid_of_name" = "$GROUP_ID" ]; then
  # Group already correctly configured
  echo "ℹ️ Group '${GROUP_NAME}' (GID ${GROUP_ID}) already exists."
  _group_already_ok=true
elif [ -n "$_gid_of_name" ] && [ "$_gid_of_name" != "$GROUP_ID" ]; then
  # Group name exists but with the wrong GID
  if [ "$REPLACE_EXISTING" = "true" ]; then
    echo "🔍 Group '${GROUP_NAME}' has GID ${_gid_of_name} (want ${GROUP_ID}) — removing."
    groupdel "$GROUP_NAME" 2> /dev/null || echo "  ⚠️ Failed to delete group '${GROUP_NAME}'." >&2
  else
    echo "⛔ Group '${GROUP_NAME}' exists with GID ${_gid_of_name} (want ${GROUP_ID}). Set replace_existing=true to override." >&2
    exit 1
  fi
elif [ -n "$_group_by_gid" ] && [ "$_group_by_gid" != "$GROUP_NAME" ]; then
  # GID is occupied by a different group
  if [ "$REPLACE_EXISTING" = "true" ]; then
    echo "🔍 GID ${GROUP_ID} is in use by group '${_group_by_gid}' — removing members and group."
    while IFS= read -r _u; do
      [ -z "$_u" ] && continue
      echo "  🧑 Removing user '${_u}' (primary group conflict)."
      userdel "$_u" 2> /dev/null || echo "  ⚠️ Failed to remove user '${_u}'." >&2
    done < <(awk -F: -v gid="$GROUP_ID" '$4 == gid {print $1}' /etc/passwd)
    groupdel "$_group_by_gid" 2> /dev/null || echo "  ⚠️ Failed to delete group '${_group_by_gid}'." >&2
  else
    echo "⛔ GID ${GROUP_ID} is already used by group '${_group_by_gid}'. Set replace_existing=true to override." >&2
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Resolve conflicts for the user account
# ---------------------------------------------------------------------------
_user_already_ok=false
_user_by_uid=$(awk -F: -v uid="$USER_ID" '$3 == uid {print $1}' /etc/passwd || true)
_uid_of_name=$(id -u "$USERNAME" 2> /dev/null || true)

if [ -n "$_uid_of_name" ] && [ "$_uid_of_name" = "$USER_ID" ]; then
  # User already correctly configured
  echo "ℹ️ User '${USERNAME}' (UID ${USER_ID}) already exists."
  _user_already_ok=true
elif [ -n "$_uid_of_name" ] && [ "$_uid_of_name" != "$USER_ID" ]; then
  # Username exists but has the wrong UID
  if [ "$REPLACE_EXISTING" = "true" ]; then
    echo "🔍 User '${USERNAME}' has UID ${_uid_of_name} (want ${USER_ID}) — removing."
    userdel "$USERNAME" 2> /dev/null || echo "  ⚠️ Failed to remove user '${USERNAME}'." >&2
  else
    echo "⛔ User '${USERNAME}' exists with UID ${_uid_of_name} (want ${USER_ID}). Set replace_existing=true to override." >&2
    exit 1
  fi
elif [ -n "$_user_by_uid" ] && [ "$_user_by_uid" != "$USERNAME" ]; then
  # UID is occupied by a different user
  if [ "$REPLACE_EXISTING" = "true" ]; then
    echo "🔍 UID ${USER_ID} is in use by '${_user_by_uid}' — removing."
    userdel "$_user_by_uid" 2> /dev/null || echo "  ⚠️ Failed to remove user '${_user_by_uid}'." >&2
  else
    echo "⛔ UID ${USER_ID} is already used by user '${_user_by_uid}'. Set replace_existing=true to override." >&2
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Create primary group
# ---------------------------------------------------------------------------
if [ "$_group_already_ok" != "true" ]; then
  echo "➕ Creating group '${GROUP_NAME}' (GID ${GROUP_ID})."
  groupadd --gid "$GROUP_ID" "$GROUP_NAME"
fi

# ---------------------------------------------------------------------------
# Create user
# ---------------------------------------------------------------------------
if [ "$_user_already_ok" != "true" ]; then
  echo "➕ Creating user '${USERNAME}' (UID=${USER_ID} GID=${GROUP_ID} home=${HOME_DIR} shell=${USER_SHELL})."
  useradd \
    --no-create-home \
    --home-dir "$HOME_DIR" \
    --gid "$GROUP_ID" \
    --shell "$USER_SHELL" \
    --uid "$USER_ID" \
    "$USERNAME"
fi

# Ensure home directory exists with correct ownership and skel contents
if [ ! -d "$HOME_DIR" ]; then
  mkdir -p "$HOME_DIR"
  cp -rn /etc/skel/. "$HOME_DIR/" 2> /dev/null || true
  chown -R "${USERNAME}:${GROUP_NAME}" "$HOME_DIR"
  echo "  🏠 Created home directory '${HOME_DIR}'."
else
  chown "${USERNAME}:${GROUP_NAME}" "$HOME_DIR"
  echo "  ℹ️ Home directory '${HOME_DIR}' already exists — ownership set."
fi

# ---------------------------------------------------------------------------
# Sudo access
# ---------------------------------------------------------------------------
if [ "$SUDO_ACCESS" = "true" ]; then
  ospkg__run --manifest "${_SELF_DIR}/../dependencies/sudo.yaml" --skip_installed
  mkdir -p "$SUDOERS_DIR"
  echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > "${SUDOERS_DIR}/${USERNAME}"
  chmod 0440 "${SUDOERS_DIR}/${USERNAME}"
  if command -v visudo > /dev/null 2>&1; then
    visudo -c -f "${SUDOERS_DIR}/${USERNAME}" || {
      echo "⛔ sudoers file validation failed." >&2
      rm -f "${SUDOERS_DIR}/${USERNAME}"
      exit 1
    }
  fi
  echo "  ✅ Granted passwordless sudo to '${USERNAME}'."
fi

# ---------------------------------------------------------------------------
# Supplementary groups
# ---------------------------------------------------------------------------
if [ "${#EXTRA_GROUPS[@]}" -gt 0 ]; then
  for _grp in "${EXTRA_GROUPS[@]}"; do
    _grp="${_grp// /}" # trim spaces
    [ -z "$_grp" ] && continue
    if ! getent group "$_grp" > /dev/null 2>&1; then
      echo "  ⚠️ Supplementary group '${_grp}' does not exist — skipping." >&2
      continue
    fi
    usermod -aG "$_grp" "$USERNAME"
    echo "  ✅ Added '${USERNAME}' to group '${_grp}'."
  done
fi

echo "✅ User '${USERNAME}' (UID=${USER_ID}, GID=${GROUP_ID}) configured successfully."
