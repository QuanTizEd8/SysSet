#!/usr/bin/env bash
# install.sh — runs as root at image build time.
#
# Creates a user account for the dev container: creates a primary group,
# creates the user with the specified UID/GID/home/shell, grants passwordless
# sudo (optional), and adds the user to supplementary groups.
#
# Feature options (injected as environment variables by the tooling):
#   USERNAME, USER_ID, GROUP_ID, GROUP_NAME, HOME_DIR, USER_SHELL,
#   SUDO_ACCESS, EXTRA_GROUPS, REPLACE_EXISTING, SUDOERS_DIR, DEBUG, LOGFILE
set -euo pipefail

# ---------------------------------------------------------------------------
# Cleanup / logging
# ---------------------------------------------------------------------------
_SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$_SELF_DIR/_lib/ospkg.sh"
. "$_SELF_DIR/_lib/logging.sh"
logging::setup

echo "↪️ Script entry: User Setup" >&2
trap 'logging::cleanup' EXIT

# ---------------------------------------------------------------------------
# Argument parsing (CLI invocation — not used by devcontainer tooling)
# ---------------------------------------------------------------------------
if [ "$#" -gt 0 ]; then
  echo "ℹ️ Script called with arguments: $*" >&2
  DEBUG=""
  EXTRA_GROUPS=""
  GROUP_ID=""
  GROUP_NAME=""
  HOME_DIR=""
  LOGFILE=""
  REPLACE_EXISTING=""
  SUDO_ACCESS=""
  SUDOERS_DIR=""
  USER_ID=""
  USER_SHELL=""
  USERNAME=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --debug)
        shift
        DEBUG=true
        ;;
      --extra_groups)
        shift
        EXTRA_GROUPS="$1"
        shift
        ;;
      --group_id)
        shift
        GROUP_ID="$1"
        shift
        ;;
      --group_name)
        shift
        GROUP_NAME="$1"
        shift
        ;;
      --home_dir)
        shift
        HOME_DIR="$1"
        shift
        ;;
      --logfile)
        shift
        LOGFILE="$1"
        shift
        ;;
      --replace_existing)
        shift
        REPLACE_EXISTING="$1"
        shift
        ;;
      --sudo_access)
        shift
        SUDO_ACCESS="$1"
        shift
        ;;
      --sudoers_dir)
        shift
        SUDOERS_DIR="$1"
        shift
        ;;
      --user_id)
        shift
        USER_ID="$1"
        shift
        ;;
      --user_shell)
        shift
        USER_SHELL="$1"
        shift
        ;;
      --username)
        shift
        USERNAME="$1"
        shift
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
  echo "ℹ️ Script called with no arguments — reading environment variables." >&2
fi

# ---------------------------------------------------------------------------
# Apply defaults
# ---------------------------------------------------------------------------
DEBUG="${DEBUG:-false}"
EXTRA_GROUPS="${EXTRA_GROUPS:-}"
GROUP_ID="${GROUP_ID:-1000}"
GROUP_NAME="${GROUP_NAME:-}"
HOME_DIR="${HOME_DIR:-}"
LOGFILE="${LOGFILE:-}"
REPLACE_EXISTING="${REPLACE_EXISTING:-true}"
SUDO_ACCESS="${SUDO_ACCESS:-true}"
SUDOERS_DIR="${SUDOERS_DIR:-/etc/sudoers.d}"
USER_ID="${USER_ID:-1000}"
USER_SHELL="${USER_SHELL:-/bin/bash}"
USERNAME="${USERNAME:-vscode}"

# Values derived from USERNAME
[ -z "$GROUP_NAME" ] && GROUP_NAME="$USERNAME"
[ -z "$HOME_DIR" ] && HOME_DIR="/home/${USERNAME}"

[[ "$DEBUG" == "true" ]] && set -x

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
os::require_root
ospkg::run --manifest "${_SELF_DIR}/../dependencies/base.txt" --check_installed

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
  ospkg::run --manifest "${_SELF_DIR}/../dependencies/sudo.txt" --check_installed
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
if [ -n "$EXTRA_GROUPS" ]; then
  IFS=',' read -ra _extra_groups <<< "$EXTRA_GROUPS"
  for _grp in "${_extra_groups[@]}"; do
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
