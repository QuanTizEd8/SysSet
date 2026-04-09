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
__cleanup__() {
  echo "↪️ Function entry: __cleanup__" >&2
  if [ -n "${LOGFILE-}" ]; then
    exec 1>&3 2>&4
    wait 2>/dev/null
    echo "ℹ️ Write logs to file '$LOGFILE'" >&2
    mkdir -p "$(dirname "$LOGFILE")"
    cat "$_LOGFILE_TMP" >> "$LOGFILE"
    rm -f "$_LOGFILE_TMP"
  fi
  echo "↩️ Function exit: __cleanup__" >&2
}

exit_if_not_root() {
  echo "↪️ Function entry: exit_if_not_root" >&2
  if [ "$(id -u)" -ne 0 ]; then
      echo '⛔ This script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.' >&2
      exit 1
  fi
  echo "↩️ Function exit: exit_if_not_root" >&2
}

_LOGFILE_TMP="$(mktemp)"
exec 3>&1 4>&2
exec > >(tee -a "$_LOGFILE_TMP" >&3) 2>&1
echo "↪️ Script entry: User Setup Devcontainer Feature Installer" >&2
trap __cleanup__ EXIT
if [ "$#" -gt 0 ]; then
  echo "ℹ️ Script called with arguments: $@" >&2
  DEBUG=""
  GID=""
  HOME_DIR=""
  LOGFILE=""
  SUDOERS_DIR=""
  UID=""
  USERNAME=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --debug) shift; DEBUG=true; echo "📩 Read argument 'debug': '${DEBUG}'" >&2;;
      --gid) shift; GID="$1"; echo "📩 Read argument 'gid': '${GID}'" >&2; shift;;
      --home_dir) shift; HOME_DIR="$1"; echo "📩 Read argument 'home_dir': '${HOME_DIR}'" >&2; shift;;
      --logfile) shift; LOGFILE="$1"; echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2; shift;;
      --sudoers_dir) shift; SUDOERS_DIR="$1"; echo "📩 Read argument 'sudoers_dir': '${SUDOERS_DIR}'" >&2; shift;;
      --uid) shift; UID="$1"; echo "📩 Read argument 'uid': '${UID}'" >&2; shift;;
      --username) shift; USERNAME="$1"; echo "📩 Read argument 'username': '${USERNAME}'" >&2; shift;;
      --*) echo "⛔ Unknown option: '${1}'" >&2; exit 1;;
      *) echo "⛔ Unexpected argument: '${1}'" >&2; exit 1;;
    esac
  done
else
  echo "ℹ️ Script called with no arguments. Read environment variables." >&2
  [ "${DEBUG+defined}" ] && echo "📩 Read argument 'debug': '${DEBUG}'" >&2
  [ "${GID+defined}" ] && echo "📩 Read argument 'gid': '${GID}'" >&2
  [ "${HOME_DIR+defined}" ] && echo "📩 Read argument 'home_dir': '${HOME_DIR}'" >&2
  [ "${LOGFILE+defined}" ] && echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2
  [ "${SUDOERS_DIR+defined}" ] && echo "📩 Read argument 'sudoers_dir': '${SUDOERS_DIR}'" >&2
  [ "${UID+defined}" ] && echo "📩 Read argument 'uid': '${UID}'" >&2
  [ "${USERNAME+defined}" ] && echo "📩 Read argument 'username': '${USERNAME}'" >&2
fi
[[ "$DEBUG" == true ]] && set -x
[ -z "${DEBUG-}" ] && { echo "ℹ️ Argument 'DEBUG' set to default value 'false'." >&2; DEBUG=false; }
[ -z "${GID-}" ] && { echo "ℹ️ Argument 'GID' set to default value '1000'." >&2; GID="1000"; }
[ -z "${HOME_DIR-}" ] && { echo "ℹ️ Argument 'HOME_DIR' set to default value '/home/vscode'." >&2; HOME_DIR="/home/vscode"; }
[ -z "${LOGFILE-}" ] && { echo "ℹ️ Argument 'LOGFILE' set to default value ''." >&2; LOGFILE=""; }
[ -z "${SUDOERS_DIR-}" ] && { echo "ℹ️ Argument 'SUDOERS_DIR' set to default value '/etc/sudoers.d'." >&2; SUDOERS_DIR="/etc/sudoers.d"; }
[ -z "${UID-}" ] && { echo "ℹ️ Argument 'UID' set to default value '1000'." >&2; UID="1000"; }
[ -z "${USERNAME-}" ] && { echo "ℹ️ Argument 'USERNAME' set to default value 'vscode'." >&2; USERNAME="vscode"; }
exit_if_not_root
GROUP_LINE=$(getent group "$GID" || true)
GROUP_NAME=$(echo "$GROUP_LINE" | cut -d: -f1)
if [ -n "$GROUP_NAME" ]; then
    echo "🔍 Found group '$GROUP_NAME' with GID '$GID'."
    USERS=$(awk -F: -v gid="$GID" '$4 == gid {print $1}' /etc/passwd)
    for user in $USERS; do
        echo "🧑 Deleting user '$user' from group."
        userdel -r "$user" 2>/dev/null || echo "⚠️ Failed to delete user '$user'."
    done
    if getent group "$GROUP_NAME" >/dev/null; then
        echo "🧺 Deleting group '$GROUP_NAME'."
        groupdel "$GROUP_NAME" 2>/dev/null || echo "⚠️  Failed to delete group '$GROUP_NAME'."
    else
        echo "ℹ️  Group '$GROUP_NAME' deleted."
    fi
else
    echo "ℹ️ No group found with GID '$GID'."
fi
USER_LINE=$(awk -F: -v uid="$UID" '$3 == uid {print $0}' /etc/passwd)
USER_NAME=$(echo "$USER_LINE" | cut -d: -f1)
if [ -n "$USER_NAME" ]; then
    echo "🔍 Found user '$USER_NAME' with UID '$UID'."
    userdel -r "$USER_NAME" 2>/dev/null || echo "⚠️ Failed to delete user '$USER_NAME'."
else
    echo "ℹ️  No additional user found with UID '$UID' to delete."
fi
groupadd --gid $GID $USERNAME;
useradd \
    --create-home \
    --home-dir "$HOME_DIR" \
    --gid $GID \
    --shell /bin/bash \
    --uid $UID \
    $USERNAME;
mkdir -p "$SUDOERS_DIR";
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" | tee "$SUDOERS_DIR/$USERNAME" > /dev/null;
chmod 0440 "$SUDOERS_DIR/$USERNAME";
echo "↩️ Script exit: User Setup Devcontainer Feature Installer" >&2
