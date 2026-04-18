#!/usr/bin/env bash
set -euo pipefail

_SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
_BASE_DIR="$(cd "$_SELF_DIR/.." && pwd)"

# shellcheck source=lib/ospkg.sh
. "$_SELF_DIR/_lib/ospkg.sh"
# shellcheck source=lib/logging.sh
. "$_SELF_DIR/_lib/logging.sh"
logging__setup
echo "↪️ Script entry: Install Homebrew" >&2
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
    echo "✅ Install Homebrew script finished successfully." >&2
  else
    echo "❌ Install Homebrew script exited with error ${_rc}." >&2
  fi
  logging__cleanup
  return
}
trap '_on_exit' EXIT

__usage__() {
  cat << 'EOF'
Usage: install.sh [OPTIONS]

Options:
  --install_user <value>              User to own the Homebrew installation.
  --prefix <value>                    Override the Homebrew installation prefix (`HOMEBREW_PREFIX`).
  --if_exists {skip|fail|reinstall}   What to do when Homebrew is already installed at the resolved prefix. (default: "skip")
  --update {true,false}               Run 'brew update' after installation to fetch the latest formula index. (default: "true")
  --export_path <value>               Controls which shell startup files receive 'eval "$(brew shellenv)"'. (default: "auto")
  --add_current_user {true,false}     Include the current user (the user running the installer, or SUDO_USER if set) in the resolved user list for shellenv exports and init-file writes. (default: "true")
  --add_remote_user {true,false}      Include the devcontainer remoteUser (from the _REMOTE_USER env var) in the resolved user list for shellenv exports and init-file writes. (default: "true")
  --add_container_user {true,false}   Include the devcontainer containerUser (from the _CONTAINER_USER env var) in the resolved user list for shellenv exports and init-file writes. (default: "true")
  --add_users <value>  (repeatable)   Additional usernames to include in the resolved user list for shellenv exports and init-file writes.
  --write_group <value>               OS group for shared write access to the Homebrew prefix. (default: "brew")
  --brew_git_remote <value>           Override `HOMEBREW_BREW_GIT_REMOTE` — the git remote for the `Homebrew/brew` repository.
  --core_git_remote <value>           Override `HOMEBREW_CORE_GIT_REMOTE` — the git remote for the `homebrew-core` tap.
  --no_install_from_api {true,false}  Set `HOMEBREW_NO_INSTALL_FROM_API=1` during installation. (default: "false")
  --keep_cache {true,false}           Keep the package manager cache after installation. By default, the package manager cache is removed after installation to reduce image layer size. Set this flag to true to keep the cache, which may speed up subsequent installations at the cost of larger image layers. (default: "false")
  --debug {true,false}                Enable debug output. This adds `set -x` to the installer script, which prints each command before executing it. (default: "false")
  --logfile <value>                   Log all output (stdout + stderr) to this file in addition to console.
  -h, --help                          Show this help
EOF
  return
}

if [ "$#" -gt 0 ]; then
  echo "ℹ️ Script called with arguments: $*" >&2
  INSTALL_USER=""
  PREFIX=""
  IF_EXISTS="skip"
  UPDATE=true
  EXPORT_PATH="auto"
  ADD_CURRENT_USER=true
  ADD_REMOTE_USER=true
  ADD_CONTAINER_USER=true
  ADD_USERS=()
  WRITE_GROUP="brew"
  BREW_GIT_REMOTE=""
  CORE_GIT_REMOTE=""
  NO_INSTALL_FROM_API=false
  KEEP_CACHE=false
  DEBUG=false
  LOGFILE=""
  while [ "$#" -gt 0 ]; do
    case $1 in
      --install_user)
        shift
        INSTALL_USER="$1"
        echo "📩 Read argument 'install_user': '${INSTALL_USER}'" >&2
        shift
        ;;
      --prefix)
        shift
        PREFIX="$1"
        echo "📩 Read argument 'prefix': '${PREFIX}'" >&2
        shift
        ;;
      --if_exists)
        shift
        IF_EXISTS="$1"
        echo "📩 Read argument 'if_exists': '${IF_EXISTS}'" >&2
        shift
        ;;
      --update)
        shift
        UPDATE="$1"
        echo "📩 Read argument 'update': '${UPDATE}'" >&2
        shift
        ;;
      --export_path)
        shift
        EXPORT_PATH="$1"
        echo "📩 Read argument 'export_path': '${EXPORT_PATH}'" >&2
        shift
        ;;
      --add_current_user)
        shift
        ADD_CURRENT_USER="$1"
        echo "📩 Read argument 'add_current_user': '${ADD_CURRENT_USER}'" >&2
        shift
        ;;
      --add_remote_user)
        shift
        ADD_REMOTE_USER="$1"
        echo "📩 Read argument 'add_remote_user': '${ADD_REMOTE_USER}'" >&2
        shift
        ;;
      --add_container_user)
        shift
        ADD_CONTAINER_USER="$1"
        echo "📩 Read argument 'add_container_user': '${ADD_CONTAINER_USER}'" >&2
        shift
        ;;
      --add_users)
        shift
        ADD_USERS+=("$1")
        echo "📩 Read argument 'add_users': '$1'" >&2
        shift
        ;;
      --write_group)
        shift
        WRITE_GROUP="$1"
        echo "📩 Read argument 'write_group': '${WRITE_GROUP}'" >&2
        shift
        ;;
      --brew_git_remote)
        shift
        BREW_GIT_REMOTE="$1"
        echo "📩 Read argument 'brew_git_remote': '${BREW_GIT_REMOTE}'" >&2
        shift
        ;;
      --core_git_remote)
        shift
        CORE_GIT_REMOTE="$1"
        echo "📩 Read argument 'core_git_remote': '${CORE_GIT_REMOTE}'" >&2
        shift
        ;;
      --no_install_from_api)
        shift
        NO_INSTALL_FROM_API="$1"
        echo "📩 Read argument 'no_install_from_api': '${NO_INSTALL_FROM_API}'" >&2
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
  [ "${INSTALL_USER+defined}" ] && echo "📩 Read argument 'install_user': '${INSTALL_USER}'" >&2
  [ "${PREFIX+defined}" ] && echo "📩 Read argument 'prefix': '${PREFIX}'" >&2
  [ "${IF_EXISTS+defined}" ] && echo "📩 Read argument 'if_exists': '${IF_EXISTS}'" >&2
  [ "${UPDATE+defined}" ] && echo "📩 Read argument 'update': '${UPDATE}'" >&2
  [ "${EXPORT_PATH+defined}" ] && echo "📩 Read argument 'export_path': '${EXPORT_PATH}'" >&2
  [ "${ADD_CURRENT_USER+defined}" ] && echo "📩 Read argument 'add_current_user': '${ADD_CURRENT_USER}'" >&2
  [ "${ADD_REMOTE_USER+defined}" ] && echo "📩 Read argument 'add_remote_user': '${ADD_REMOTE_USER}'" >&2
  [ "${ADD_CONTAINER_USER+defined}" ] && echo "📩 Read argument 'add_container_user': '${ADD_CONTAINER_USER}'" >&2
  if [ "${ADD_USERS+defined}" ]; then
    if [ -n "${ADD_USERS-}" ]; then
      mapfile -t ADD_USERS < <(printf '%s\n' "${ADD_USERS}" | grep -v '^$')
      for _item in "${ADD_USERS[@]}"; do
        echo "📩 Read argument 'add_users': '$_item'" >&2
      done
    else
      ADD_USERS=()
    fi
  fi
  [ "${WRITE_GROUP+defined}" ] && echo "📩 Read argument 'write_group': '${WRITE_GROUP}'" >&2
  [ "${BREW_GIT_REMOTE+defined}" ] && echo "📩 Read argument 'brew_git_remote': '${BREW_GIT_REMOTE}'" >&2
  [ "${CORE_GIT_REMOTE+defined}" ] && echo "📩 Read argument 'core_git_remote': '${CORE_GIT_REMOTE}'" >&2
  [ "${NO_INSTALL_FROM_API+defined}" ] && echo "📩 Read argument 'no_install_from_api': '${NO_INSTALL_FROM_API}'" >&2
  [ "${KEEP_CACHE+defined}" ] && echo "📩 Read argument 'keep_cache': '${KEEP_CACHE}'" >&2
  [ "${DEBUG+defined}" ] && echo "📩 Read argument 'debug': '${DEBUG}'" >&2
  [ "${LOGFILE+defined}" ] && echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2
fi

[[ "${DEBUG:-}" == true ]] && set -x

# Apply defaults.
[ "${INSTALL_USER+defined}" ] || {
  INSTALL_USER=""
  echo "ℹ️ Argument 'install_user' set to default value ''." >&2
}
[ "${PREFIX+defined}" ] || {
  PREFIX=""
  echo "ℹ️ Argument 'prefix' set to default value ''." >&2
}
[ "${IF_EXISTS+defined}" ] || {
  IF_EXISTS="skip"
  echo "ℹ️ Argument 'if_exists' set to default value 'skip'." >&2
}
[ "${UPDATE+defined}" ] || {
  UPDATE=true
  echo "ℹ️ Argument 'update' set to default value 'true'." >&2
}
[ "${EXPORT_PATH+defined}" ] || {
  EXPORT_PATH="auto"
  echo "ℹ️ Argument 'export_path' set to default value 'auto'." >&2
}
[ "${ADD_CURRENT_USER+defined}" ] || {
  ADD_CURRENT_USER=true
  echo "ℹ️ Argument 'add_current_user' set to default value 'true'." >&2
}
[ "${ADD_REMOTE_USER+defined}" ] || {
  ADD_REMOTE_USER=true
  echo "ℹ️ Argument 'add_remote_user' set to default value 'true'." >&2
}
[ "${ADD_CONTAINER_USER+defined}" ] || {
  ADD_CONTAINER_USER=true
  echo "ℹ️ Argument 'add_container_user' set to default value 'true'." >&2
}
[ "${ADD_USERS+defined}" ] || {
  ADD_USERS=()
  echo "ℹ️ Argument 'add_users' set to default value '(empty)'." >&2
}
[ "${WRITE_GROUP+defined}" ] || {
  WRITE_GROUP="brew"
  echo "ℹ️ Argument 'write_group' set to default value 'brew'." >&2
}
[ "${BREW_GIT_REMOTE+defined}" ] || {
  BREW_GIT_REMOTE=""
  echo "ℹ️ Argument 'brew_git_remote' set to default value ''." >&2
}
[ "${CORE_GIT_REMOTE+defined}" ] || {
  CORE_GIT_REMOTE=""
  echo "ℹ️ Argument 'core_git_remote' set to default value ''." >&2
}
[ "${NO_INSTALL_FROM_API+defined}" ] || {
  NO_INSTALL_FROM_API=false
  echo "ℹ️ Argument 'no_install_from_api' set to default value 'false'." >&2
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

# Validate enum options.
case "${IF_EXISTS}" in
  skip | fail | reinstall) ;;
  *)
    echo "⛔ Invalid value for 'if_exists': '${IF_EXISTS}' (expected: skip, fail, reinstall)" >&2
    exit 1
    ;;
esac

ospkg__run --manifest "${_BASE_DIR}/dependencies/base.yaml" --skip_installed

# END OF AUTOGENERATED BLOCK

# ── Constants ────────────────────────────────────────────────────────────────
_BREW_INSTALL_BASE_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD"
_BREW_INSTALLER_URL="${_BREW_INSTALL_BASE_URL}/install.sh"
_BREW_UNINSTALLER_URL="${_BREW_INSTALL_BASE_URL}/uninstall.sh"

# ── High-level steps ──────────────────────────────────────────────────────────

install_linux_deps() {
  echo "↪️ Function entry: install_linux_deps" >&2
  echo "📦 Installing Homebrew build dependencies." >&2
  ospkg__run --manifest "${_BASE_DIR}/dependencies/base.yaml" --skip_installed
  echo "↩️ Function exit: install_linux_deps" >&2
  return 0
}

run_brew_installer() {
  echo "↪️ Function entry: run_brew_installer" >&2
  echo "📦 Running Homebrew installer as user '${RESOLVED_INSTALL_USER}'." >&2
  local -a _env_vars=("NONINTERACTIVE=1")
  [ -n "${BREW_GIT_REMOTE-}" ] && _env_vars+=("HOMEBREW_BREW_GIT_REMOTE=${BREW_GIT_REMOTE}")
  [ -n "${CORE_GIT_REMOTE-}" ] && _env_vars+=("HOMEBREW_CORE_GIT_REMOTE=${CORE_GIT_REMOTE}")
  [[ "${NO_INSTALL_FROM_API}" == true ]] && _env_vars+=("HOMEBREW_NO_INSTALL_FROM_API=1")
  [ -n "${PREFIX-}" ] && _env_vars+=("HOMEBREW_PREFIX=${PREFIX}")
  local _tmpfile
  _tmpfile="$(mktemp /tmp/brew_install.XXXXXX.sh)"
  # shellcheck disable=SC2064
  trap "rm -f '${_tmpfile}'" RETURN
  echo "📥 Downloading Homebrew installer to '${_tmpfile}'." >&2
  net__fetch_url_file "$_BREW_INSTALLER_URL" "$_tmpfile"
  chmod a+r "$_tmpfile"
  echo "ℹ️ Installing as '${RESOLVED_INSTALL_USER}'." >&2
  _brew_run_as_install_user env "${_env_vars[@]}" /bin/bash "$_tmpfile"
  echo "✅ Homebrew installer completed." >&2
  echo "↩️ Function exit: run_brew_installer" >&2
  return 0
}

uninstall_brew() {
  echo "↪️ Function entry: uninstall_brew" >&2
  echo "🗑 Uninstalling Homebrew at '${RESOLVED_PREFIX}'." >&2
  local _tmpfile
  _tmpfile="$(mktemp /tmp/brew_uninstall.XXXXXX.sh)"
  # shellcheck disable=SC2064
  trap "rm -f '${_tmpfile}'" RETURN
  net__fetch_url_file "$_BREW_UNINSTALLER_URL" "$_tmpfile"
  chmod a+r "$_tmpfile"
  _brew_run_as_install_user env NONINTERACTIVE=1 /bin/bash "$_tmpfile" --path "$RESOLVED_PREFIX"
  echo "✅ Homebrew uninstalled." >&2
  echo "↩️ Function exit: uninstall_brew" >&2
  return 0
}

export_shellenv_for_user() {
  echo "↪️ Function entry: export_shellenv_for_user" >&2
  local _user="$1"
  # shellcheck disable=SC2016  # shellcheck disable=SC2016  local _brew_content='eval "$('''${RESOLVED_PREFIX}/bin/brew''' shellenv)"'
  shell__sync_block \
    --files "$(shell__user_init_files --home "$(shell__resolve_home "$_user")")" \
    --marker "brew shellenv (install-homebrew)" \
    --content "$_brew_content"
  echo "↩️ Function exit: export_shellenv_for_user" >&2
  return 0
}

export_shellenv_main() {
  echo "↪️ Function entry: export_shellenv_main" >&2
  if [ "$EXPORT_PATH" = "" ]; then
    echo "ℹ️ export_path is empty; skipping shellenv export." >&2
    echo "↩️ Function exit: export_shellenv_main" >&2
    return 0
  fi
  # shellcheck disable=SC2016
  local _brew_content='eval "$('"${RESOLVED_PREFIX}/bin/brew"' shellenv)"'
  local _marker="brew shellenv (install-homebrew)"
  if [ "$EXPORT_PATH" != "auto" ]; then
    # Explicit newline-separated path list
    shell__sync_block --files "$EXPORT_PATH" --marker "$_marker" --content "$_brew_content"
    echo "↩️ Function exit: export_shellenv_main" >&2
    return 0
  fi
  # auto mode
  local _is_root=false
  [ "$(id -u)" = "0" ] && _is_root=true
  if [ "$_is_root" = true ] && [ "$(os__kernel)" != "Darwin" ]; then
    echo "ℹ️ Case A: system-wide shellenv export (root + Linux)." >&2
    shell__sync_block \
      --files "$(shell__system_path_files --profile_d "brew.sh")" \
      --marker "$_marker" \
      --content "$_brew_content"
  else
    echo "ℹ️ Case B: user-scoped shellenv export." >&2
    export_shellenv_for_user "$RESOLVED_INSTALL_USER"
  fi
  # Resolved additional users
  local _u
  while IFS= read -r _u; do
    [[ -z "$_u" ]] && continue
    echo "ℹ️ Exporting shellenv for resolved user '${_u}'." >&2
    export_shellenv_for_user "$_u"
  done < <(users__resolve_list)
  echo "↩️ Function exit: export_shellenv_main" >&2
  return 0
}

# ── Helper functions ──────────────────────────────────────────────────────────

detect_brew_prefix() {
  echo "↪️ Function entry: detect_brew_prefix" >&2
  if [ "$(os__kernel)" = "Darwin" ]; then
    if [ "$(os__arch)" = "arm64" ]; then
      echo "/opt/homebrew"
    else
      echo "/usr/local"
    fi
  else
    echo "/home/linuxbrew/.linuxbrew"
  fi
  echo "↩️ Function exit: detect_brew_prefix" >&2
  return 0
}

# Returns the path to the Homebrew/brew git repository — distinct from the
# prefix on Intel macOS and Linux, where brew lives in ${prefix}/Homebrew.
detect_brew_repository() {
  echo "↪️ Function entry: detect_brew_repository" >&2
  if [ "$(os__kernel)" = "Darwin" ] && [ "$(os__arch)" = "arm64" ]; then
    echo "${RESOLVED_PREFIX}"
  else
    echo "${RESOLVED_PREFIX}/Homebrew"
  fi
  echo "↩️ Function exit: detect_brew_repository" >&2
  return 0
}

# enforce_options — applies post-install options unconditionally:
#   • BREW_GIT_REMOTE / CORE_GIT_REMOTE: sets git remote.origin.url on the
#     brew and homebrew-core repositories, and writes env-var export blocks to
#     shell init files (so future `brew update` calls use the same remote).
#   • NO_INSTALL_FROM_API: writes / removes HOMEBREW_NO_INSTALL_FROM_API=1
#     export block in shell init files.
enforce_options() {
  echo "↪️ Function entry: enforce_options" >&2
  local _brew_repo _core_repo _marker_brew _marker_core _marker_api
  _brew_repo="$(detect_brew_repository)"
  _core_repo="${_brew_repo}/Library/Taps/homebrew/homebrew-core"
  _marker_brew="HOMEBREW_BREW_GIT_REMOTE (install-homebrew)"
  _marker_core="HOMEBREW_CORE_GIT_REMOTE (install-homebrew)"
  _marker_api="HOMEBREW_NO_INSTALL_FROM_API (install-homebrew)"

  # --- brew git remote ---
  if [ -n "${BREW_GIT_REMOTE-}" ]; then
    echo "🔧 Setting brew git remote to '${BREW_GIT_REMOTE}'." >&2
    if [ -d "${_brew_repo}/.git" ]; then
      git -C "$_brew_repo" remote set-url origin "$BREW_GIT_REMOTE"
    else
      echo "⚠️ brew repository not found at '${_brew_repo}'; skipping git remote set." >&2
    fi
  fi
  _sync_init_files "$_marker_brew" ${BREW_GIT_REMOTE:+"export HOMEBREW_BREW_GIT_REMOTE=\"${BREW_GIT_REMOTE}\""}

  # --- core git remote ---
  if [ -n "${CORE_GIT_REMOTE-}" ]; then
    echo "🔧 Setting homebrew-core git remote to '${CORE_GIT_REMOTE}'." >&2
    if [ -d "${_core_repo}/.git" ]; then
      git -C "$_core_repo" remote set-url origin "$CORE_GIT_REMOTE"
    else
      echo "ℹ️ homebrew-core tap not present at '${_core_repo}'; skipping git remote set." >&2
    fi
  fi
  _sync_init_files "$_marker_core" ${CORE_GIT_REMOTE:+"export HOMEBREW_CORE_GIT_REMOTE=\"${CORE_GIT_REMOTE}\""}

  # --- HOMEBREW_NO_INSTALL_FROM_API ---
  if [[ "${NO_INSTALL_FROM_API}" == true ]]; then
    echo "🔧 Persisting HOMEBREW_NO_INSTALL_FROM_API=1." >&2
    _sync_init_files "$_marker_api" "export HOMEBREW_NO_INSTALL_FROM_API=1"
  else
    _sync_init_files "$_marker_api"
  fi

  echo "↩️ Function exit: enforce_options" >&2
  return 0
}

# _sync_init_files <marker> [content]
# Calls shell__sync_block for the relevant init files for RESOLVED_INSTALL_USER
# (and any resolved users) plus system-wide files when running as root on Linux.
# If content is given, writes/updates the block; if absent, removes it.
_sync_init_files() {
  local _marker="$1"
  local _content="${2-}"
  local _has_content=false
  [ $# -ge 2 ] && _has_content=true
  local _files _slug _is_root=false
  [ "$(id -u)" = "0" ] && _is_root=true

  if [ "$_is_root" = true ] && [ "$(os__kernel)" != "Darwin" ]; then
    _slug="$(echo "$_marker" | tr ' ()' '_' | tr -s '_' | tr '[:upper:]' '[:lower:]')"
    _files="$(shell__system_path_files --profile_d "${_slug}.sh")"
  else
    _files="$(shell__user_init_files --home "$(shell__resolve_home "$RESOLVED_INSTALL_USER")")"
  fi
  if [ "$_has_content" = true ]; then
    shell__sync_block --files "$_files" --marker "$_marker" --content "$_content"
  else
    shell__sync_block --files "$_files" --marker "$_marker"
  fi

  local _u
  while IFS= read -r _u; do
    [[ -z "$_u" ]] && continue
    _files="$(shell__user_init_files --home "$(shell__resolve_home "$_u")")"
    if [ "$_has_content" = true ]; then
      shell__sync_block --files "$_files" --marker "$_marker" --content "$_content"
    else
      shell__sync_block --files "$_files" --marker "$_marker"
    fi
  done < <(users__resolve_list)
  return 0
}

# _brew_run_as_install_user <cmd> [args...]
# Run a command as RESOLVED_INSTALL_USER when the current process is root and
# the install user is not root. Uses runuser(1) on Linux (no sudo config
# needed for root) and sudo on macOS (runuser is absent there).
_brew_run_as_install_user() {
  echo "↪️ Function entry: _brew_run_as_install_user" >&2
  if [ "$(id -u)" != "0" ] || [ "${RESOLVED_INSTALL_USER}" = "root" ]; then
    "$@"
  elif [ "$(os__kernel)" = "Darwin" ]; then
    sudo -u "${RESOLVED_INSTALL_USER}" "$@"
  else
    runuser -u "${RESOLVED_INSTALL_USER}" -- "$@"
  fi
  echo "↩️ Function exit: _brew_run_as_install_user" >&2
  return 0
}

detect_install_user() {
  echo "↪️ Function entry: detect_install_user" >&2
  if [ -n "${INSTALL_USER-}" ]; then
    echo "ℹ️ Using specified install_user: '${INSTALL_USER}'." >&2
    echo "$INSTALL_USER"
    echo "↩️ Function exit: detect_install_user" >&2
    return 0
  fi
  if [ "$(id -u)" != "0" ]; then
    id -nu
    echo "↩️ Function exit: detect_install_user" >&2
    return 0
  fi
  # Running as root.
  if [ "$(os__kernel)" = "Darwin" ]; then
    # The official Homebrew installer refuses to run as root on macOS.
    # We must find a non-root user to install as.
    if [ -n "${SUDO_USER-}" ] && [ "$SUDO_USER" != "root" ]; then
      echo "ℹ️ macOS root: using SUDO_USER='${SUDO_USER}' as install_user." >&2
      echo "$SUDO_USER"
    else
      local _u
      _u="$(dscl . list /Users 2> /dev/null |
        grep -v -E '^(_|daemon|nobody|root|Guest)' |
        head -1)" || true
      if [ -n "$_u" ]; then
        echo "ℹ️ macOS root: using first non-system user '${_u}' as install_user." >&2
        echo "$_u"
      else
        echo "⛔ Running as root on macOS but no non-root user found." >&2
        echo "   Set the 'install_user' option to a non-root user account." >&2
        exit 1
      fi
    fi
  else
    # Linux: Homebrew's installer refuses root in container environments where
    # /.dockerenv is absent (Docker BuildKit + cgroup v2 on modern GHA runners).
    # Prefer an existing non-root user; fall back to creating a dedicated
    # 'linuxbrew' user only when no real user is available.
    if [ -n "${SUDO_USER-}" ] && [ "$SUDO_USER" != "root" ]; then
      echo "ℹ️ Linux root: using SUDO_USER='${SUDO_USER}' as install_user." >&2
      echo "$SUDO_USER"
    elif [ -n "${_REMOTE_USER-}" ] && [ "$_REMOTE_USER" != "root" ]; then
      echo "ℹ️ Linux root: using _REMOTE_USER='${_REMOTE_USER}' as install_user." >&2
      echo "$_REMOTE_USER"
    else
      if ! id linuxbrew &> /dev/null; then
        echo "ℹ️ Linux root: creating 'linuxbrew' user for Homebrew installation." >&2
        useradd --create-home --shell /bin/bash linuxbrew
        # Ubuntu 22.04+ creates home directories with mode 750; make it
        # world-traversable so other users can access the brew binary.
        chmod 755 /home/linuxbrew
      else
        echo "ℹ️ Linux root: 'linuxbrew' user already exists." >&2
      fi
      echo "linuxbrew"
    fi
  fi
  echo "↩️ Function exit: detect_install_user" >&2
  return 0
}

# shellcheck source=lib/shell.sh
. "$_SELF_DIR/_lib/shell.sh"
# shellcheck source=lib/users.sh
. "$_SELF_DIR/_lib/users.sh"

# ── Resolve prefix and install user ──────────────────────────────────────────
if [ -n "$PREFIX" ]; then
  RESOLVED_PREFIX="$PREFIX"
  echo "ℹ️ Using explicit prefix: '${RESOLVED_PREFIX}'." >&2
elif command -v brew > /dev/null 2>&1; then
  RESOLVED_PREFIX="$(brew --prefix)"
  echo "ℹ️ Detected existing brew prefix: '${RESOLVED_PREFIX}'." >&2
else
  RESOLVED_PREFIX="$(detect_brew_prefix)"
  echo "ℹ️ Using platform-default prefix: '${RESOLVED_PREFIX}'." >&2
fi

RESOLVED_INSTALL_USER="$(detect_install_user)"
echo "ℹ️ Install user: '${RESOLVED_INSTALL_USER}'." >&2

# ── Step 1: Linux build dependencies ─────────────────────────────────────────
if [ "$(os__kernel)" != "Darwin" ]; then
  install_linux_deps
fi

# ── Step 2: Install / skip / reinstall Homebrew ───────────────────────────────
_BREW_EXEC="${RESOLVED_PREFIX}/bin/brew"
if [ -f "$_BREW_EXEC" ]; then
  echo "⚠️ Homebrew found at '${_BREW_EXEC}'." >&2
  case "$IF_EXISTS" in
    skip)
      echo "⏭️ if_exists=skip: existing Homebrew detected; skipping installer and continuing to post-install steps." >&2
      ;;
    fail)
      echo "⛔ if_exists=fail: Homebrew already installed at '${RESOLVED_PREFIX}'." >&2
      echo "   Remove it first or set if_exists=skip or if_exists=reinstall." >&2
      exit 1
      ;;
    reinstall)
      echo "ℹ️ if_exists=reinstall: uninstalling then reinstalling Homebrew." >&2
      uninstall_brew
      run_brew_installer
      ;;
    *)
      echo "⛔ Invalid value for 'if_exists': '${IF_EXISTS}'. Use 'skip', 'fail', or 'reinstall'." >&2
      exit 1
      ;;
  esac
else
  run_brew_installer
fi

# ── Step 3: Verify brew executable ───────────────────────────────────────────
if [ ! -f "$_BREW_EXEC" ]; then
  echo "⛔ Homebrew executable not found at '${_BREW_EXEC}' after installation." >&2
  exit 1
fi
echo "✅ Homebrew $("$_BREW_EXEC" --version | head -1) is available at '${_BREW_EXEC}'." >&2

# ── Step 3.5: Enforce options (git remotes, NO_INSTALL_FROM_API) ──────────────
# Runs unconditionally so options are applied even when if_exists=skip.
enforce_options

# ── Step 4: brew update ───────────────────────────────────────────────────────
if [[ "$UPDATE" == true ]]; then
  echo "🔄 Running 'brew update'." >&2
  _brew_run_as_install_user "$_BREW_EXEC" update
  echo "✅ brew update completed." >&2
fi

# ── Step 5: Export shellenv ───────────────────────────────────────────────────
export_shellenv_main

# ── Step 6: brew doctor (warn only) ──────────────────────────────────────────
echo "ℹ️ Running 'brew doctor' (warnings only)." >&2
_brew_run_as_install_user "$_BREW_EXEC" doctor 2>&1 || true

# ── Step 7: Write-permission group ───────────────────────────────────────────
if [[ -n "${WRITE_GROUP:-}" ]] && [[ "$(os__kernel)" = "Linux" ]]; then
  export ADD_CURRENT_USER ADD_REMOTE_USER ADD_CONTAINER_USER ADD_USERS
  mapfile -t _write_users < <(users__resolve_list)
  users__set_write_permissions "$PREFIX" "$RESOLVED_INSTALL_USER" "$WRITE_GROUP" "${_write_users[@]}"
fi
